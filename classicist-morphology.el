;;; classicist-morphology.el --- Morphological analysis and dictionary lookup for diogenes.el -*- lexical-binding: t -*-

;; Copyright (C) 2024 Michael Neidhart
;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Michael Neidhart <mayhoth@gmail.com>
;; Keywords: classics, tools, philology, humanities

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

;; This file contains functions that can can use the lexica and morphological analyses that come with Diogenes

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'shr)                          ; for the shr-h1/h2/h3 faces used below
(require 'diogenes-lisp-utils)
(require 'classicist-variants)  ; the spellings a word might be keyed under
(require 'classicist-lexicon)   ; reading a dictionary file
(require 'classicist-lookup)    ; the buffer an entry is read in
(require 'diogenes-utils)
(require 'diogenes-perl-interface)

;; Called across files that cannot be required from here without a
;; cycle, and -- where the name is one of this package's own caches --
;; defined inside a `let', which the compiler does not count as a
;; definition at all.
(declare-function classicist-browser--word-at-point-joined "classicist-browser" ())
(defvar classicist-browser-join-broken-words)
(declare-function classicist--browse-work "classicist-browser" (options passage))
(declare-function diogenes--perseus-path "classicist" ())
(declare-function diogenes--dict-file "classicist" (lang))
(declare-function classicist--get-all-analyses "classicist-lookup" (lang))
(declare-function classicist--get-all-lemmata "classicist-lookup" (lang))
(declare-function classicist--get-analyses-index "classicist-lookup" (lang))
(declare-function classicist--all-matches-in-hashtable "classicist-morphology" (query hash-table filter ignore-case no-diacritics))
(declare-function classicist--lookup-insert-xml "classicist-lookup" (xml start end buffer))

(declare-function rng-first-error "rng-valid" ())
(declare-function classicist-perseus-action "classicist-lookup" (char))
(declare-function diogenes-lookup-open-old "diogenes-old" (&optional word))
(declare-function diogenes-lookup-open-tll "diogenes-tll" (&optional word))
(declare-function diogenes-lookup-open-montanari "diogenes-montanari" (&optional word))
(declare-function diogenes-lookup-open-cambridge "diogenes-cambridge" (&optional word))
(declare-function diogenes-lookup-open-bailly-pdf "diogenes-bailly-pdf" (&optional word))
(declare-function diogenes-lookup-gaffiot "diogenes-gaffiot" (&optional word))
(declare-function diogenes-gaffiot-lookup-buffer-p "diogenes-gaffiot" ())
(declare-function diogenes-lookup-open-gaffiot-pdf "diogenes-gaffiot-pdf"
                  (&optional word))
(declare-function diogenes-lookup-open-bdag "diogenes-bdag" (&optional word))
(declare-function diogenes-lookup-open-passow "diogenes-passow" (&optional word))
(declare-function diogenes-lookup-open-tgl "diogenes-tgl" (&optional word))
(declare-function diogenes-lookup-pape "diogenes-pape" (&optional word))
(declare-function diogenes-lookup-lsj "diogenes-pape" (&optional word))
(declare-function diogenes-pape-lookup-buffer-p "diogenes-pape" ())

;;;; --------------------------------------------------------------------
;;;; UTILITIES
;;;; --------------------------------------------------------------------


;;;; --------------------------------------------------------------------
;;;; Low LEVEL INTERFACE
;;;; --------------------------------------------------------------------

;;; "Readline"

;;; Binary search
;; Sort functions
;; ASCII

;; C, i.e. raw byte order

;;; BETA CODE

;; Key function

;; The actual search function


;;; Parse whole files and load them into memory

;;; Get file indices


;;;; --------------------------------------------------------------------
;;;; PERSEUS DICTIONARY LOOKUP
;;;; --------------------------------------------------------------------

;;; Format and insert contents

;;; Parse XML


;;; Let the user handle corrupt XML
;;; ... in the lookup mode


;;; ... in a dedicated NXML buffer


;;;###autoload


(classicist--lookup-register-shipped-dictionaries)


;;;###autoload


(defun classicist--lookup-lemma-of (word lang)
  "The lemma of WORD in LANG, or WORD itself if it will not parse.
A dictionary is keyed by headword, and the word under point is usually
inflected, so `C-c C-c\=' parses before it looks anything up.  The same
courtesy is due a dictionary chosen by hand: `\\=e)poi/hsen\\=' should reach
`poie/w\\=', not fail to be a headword.

The whole apparatus is used -- the shipped analyses, the spelling variants,
Morpheus where it is available -- but only the first analysis is taken.
Where a form is ambiguous this picks the commonest reading rather than
asking, which is the right trade for a key whose purpose is to get you into
another dictionary quickly; `C-u\=' prompts for a word if the guess is wrong."
  (or (let ((raw (classicist--do-parse word lang)))
	(when raw
	  (let* ((record (classicist--parse-analyses-record raw lang))
		 (first (car (plist-get record :analyses))))
	    (when first
	      ;; Two conversions, and neither is optional.
	      ;;
	      ;; `:lemma' holds the field as the analyses file writes it, which
	      ;; is the pair FORM,LEMMA -- "dei/knu_mi,dei/knumi" -- so the
	      ;; lemma is what follows the comma, as make_latin_analyses.pl
	      ;; also takes it (s/^.*,\s*//).  Handing a dictionary the whole
	      ;; pair asks it about a string with a comma in the middle.
	      ;;
	      ;; And the field is beta code for Greek, where the dictionary
	      ;; commands expect what `classicist--lookup-current-headword' hands
	      ;; them interactively: Unicode.  Each converts Unicode to its own
	      ;; key, so given beta code they read ASCII letters as Greek and
	      ;; land somewhere arbitrary -- consistently arbitrary across all
	      ;; of them, which is why Bailly, Pape, the LSJ and the DGE
	      ;; answered `δείκνυμι' alike with the neighbourhood of
	      ;; `δίξεστον'.
	      (let* ((field (plist-get first :lemma))
		     (lemma (if (string-match "," field)
				(substring field (match-end 0))
			      field)))
		(classicist--munge-ls-lemma (string-trim lemma) lang))))))
      (and (fboundp 'classicist--extra-lemma)
	   (classicist--extra-lemma word lang))
      ;; Morpheus, which the two lines above and the parse before them have
      ;; between them failed to answer for.  The order is
      ;; `classicist--parse-and-lookup''s: the shipped analyses, then the
      ;; hand-written table, then the cruncher.
      ;;
      ;; Without this the promise of the docstring was not kept, and the
      ;; consequence was worse than a form that would not resolve.  A
      ;; dictionary is keyed by headword; handed an inflected form it does
      ;; not have, it reports no exact entry -- and Gaffiot, told there is no
      ;; entry, opens the printed page instead.  So `C-c C-o' on
      ;; `frugalitatis', a form the wordlists never harvested, showed a scan
      ;; of the page rather than the article on `frugalitas', with nothing
      ;; said about why.
      (and (classicist-morpheus-available-p)
	   (let ((first (car (classicist--morpheus-analyses word lang))))
	     (when first
	       (let* ((field (plist-get first :lemma))
		      (lemma (if (string-match "," field)
				 (substring field (match-end 0))
			       field)))
		 (classicist--munge-ls-lemma (string-trim lemma) lang)))))
      word))


;;;###autoload

;;;###autoload


;;; LOOKUP MODE


(classicist--lookup-install-registered-keys)


;;;; --------------------------------------------------------------------
;;;; PERSEUS PARSING
;;;; --------------------------------------------------------------------

;;; Cached functions for information retrieval


;;; Analysis mode
;; TODO: This should be made better
;; - Inhibit editing the invisible text
;; - org-mode-style  visibility cycling
;; - etc.
(defun classicist-analysis-cycle (pos)
  "On a heading in analysis mode, show or hide its contents."
  (interactive "d")
  (when-let* ((level (get-char-property pos 'heading))
	     (region-start (next-single-property-change pos level))
	     (region-end (or (next-single-property-change region-start level)
			     (point-max))))
    (put-text-property region-start region-end 'invisible
		       (if (get-text-property region-start 'invisible)
			   nil t))))

(defvar classicist-analysis-mode-map
  (let ((map (nconc (make-sparse-keymap) text-mode-map)))
    (keymap-set map "TAB"  #'classicist-analysis-cycle)
    map)
  "Basic mode map for the Diogenes Analysis Mode.")

(define-derived-mode classicist-analysis-mode text-mode "Diogenes Analysis"
  "Display analysis of search term.")


(defun classicist--process-parse-result (encoded-str lang)
  "Split a bytestring as retrieved form the analyses file into a
list of the corresponding entries. Each entry consists of the headword, the
lemma, the lemma-number, translation and analysis."
  (cl-loop with str = (decode-coding-string encoded-str 'utf-8)
	   for entry in (split-string (cadr (diogenes--split-once "\t+" str))
				      ;; Remove also trailing [\d+] after }
				      "[{}]\\(?:\\[[0-9]+\\]\\)*"
				      t "\\s-")
	   for (lemma-str translation analysis) = (split-string entry "\t" nil "\\s-")
	   for (lemma-nr lemma-cat headword-and-lemma) = (split-string lemma-str)
	   for (headword lemma) = (split-string headword-and-lemma "," t "\\s-")
	   collect (list headword
			 lemma
			 lemma-nr
			 translation
			 analysis)))

(defun classicist--process-lemma (lemma lang)
  "Process a lemma entry as returned from `classicist--get-all-lemmata'.
Returns a list with the form (lemma raw-lemma lemma-nr &rest analyses)"
  (when lemma
    (nconc (list (classicist--perseus-ensure-utf8 (car lemma)
						lang)
		 (car lemma)
		 (cadr lemma))
	   (mapcar (lambda (e)
		     (seq-let (form analysis)
			 (diogenes--split-once "\\s-" e)
		       (cons (classicist--perseus-ensure-utf8 form lang)
			     (with-temp-buffer
			       (insert analysis)
			       (goto-char (point-min))
			       (cl-loop with substrings
					for pos = (scan-sexps (point) 1)
					if pos
					collect (buffer-substring (1+ (point))
								  (1- pos))
					into substrings
					else return substrings
					do (goto-char (1+ pos)))))))
		   (cddr lemma)))))

;;; Parsing functions

(defun classicist--parse-word-keys (normalized lang)
  "The keys to try for NORMALIZED, in order.
The form as it stands first, so nothing that works today stops working.  Then,
for Greek, the form with an enclitic\='s accent taken off -- see
`classicist--beta-drop-extra-accents\='."
  (let ((keys (list normalized)))
    (when (string= lang "greek")
      (let ((dropped (classicist--beta-drop-extra-accents normalized)))
        (unless (equal dropped normalized)
          (setq keys (append keys (list dropped))))))
    keys))

(defun classicist--parse-word (word lang)
  "Search the ananlyses file of lang for word using a binary search.
Returns the nearest hit to the query.

Every key `classicist--parse-word-keys\=' offers is tried before a miss is
reported, so a word carrying an enclitic\='s second accent is found under its own
spelling rather than answered with its alphabetical neighbour."
  (let* ((normalized (downcase (diogenes--beta-normalize-gravis
				(diogenes--greek-ensure-beta word))))
	 (analyses-file (file-name-concat (diogenes--perseus-path)
					  (concat lang "-analyses.txt")))
	 (index (classicist--get-analyses-index lang))
	 (keys (classicist--parse-word-keys normalized lang))
	 nearest)
    (cl-loop for candidate in keys
	     for key = (if (> (length candidate) 3)
			   (substring candidate 0 3)
			 candidate)
	     for start = (let ((s (cdr (assoc key (plist-get index :index-start)))))
			   (if s (- s 2) 0))
	     for end = (or (cdr (assoc key (plist-get index :index-end)))
			   (plist-get index :index-max))
	     for result = (classicist--binary-search analyses-file
						   #'classicist--c-sort-function
						   #'classicist--tab-key-fn
						   candidate
						   start end)
	     ;; The first miss is kept: where every key misses, the nearest entry
	     ;; to the word AS WRITTEN is the one to show, not the nearest to a
	     ;; spelling the reader never typed.
	     do (unless nearest (setq nearest result))
	     when (nth 3 result) return (classicist--parse-word-result result lang)
	     finally return (progn
			      (message "No result for %s! Showing nearest entry" word)
			      (classicist--parse-word-result nearest lang)))))

(defun classicist--parse-word-result (result lang)
  "RESULT from the binary search, shaped as `classicist--parse-word\=' returns it."
  (cons (and (car result)
	     (classicist--process-parse-result (car result) lang))
	(cdr result)))

(let ((cache (make-hash-table :test 'equal)))
 (defun classicist--all-matches-in-hashtable (query hash-table filter ignore-case no-diacritics)
   "Search for all entries in the table where querey matches the key via filter.
Additionally, letter case and diacritics can be ignored."
   (let* ((filter (or filter #'string-equal))
	  (ignore-case (and ignore-case t))
	  (no-diacritics (and no-diacritics t))
	  (transformation (cond ((and ignore-case no-diacritics)
				 (lambda (x) (downcase (diogenes--ascii-alpha-only x))))
				(ignore-case #'downcase)
				(no-diacritics #'diogenes--ascii-alpha-only)))
	  (query (if (not (or ignore-case no-diacritics))
		     query
		   (funcall transformation query)))
	  (hash (if (not (or ignore-case no-diacritics))
		    hash-table
		  (or (gethash (list hash-table ignore-case no-diacritics) cache)
		      (setf (gethash (list hash-table ignore-case no-diacritics) cache)
			    (cl-loop with hash =
				     (make-hash-table :test 'equal :size 50000)
				     for k being the hash-keys of hash-table
				     do (push k
					      (gethash (funcall transformation k) hash))
				     finally return hash)))))
	  (results (if (eq filter #'string-equal)
		       (when-let* ((entry (gethash query hash)))
			 (list (cons query entry)))
		     (cl-loop for k being the hash-keys of hash
			      using (hash-values v)
			      when (funcall filter query k)
			      collect (cons k v)))))
     (if (not (or ignore-case no-diacritics))
	 results
       (cl-loop for (q . keys) in results append
		(cl-loop for key in keys collect
			 (cons key (gethash key hash-table))))))))

(defun classicist--parse-all (query lang &optional filter ignore-case no-diacritics)
   "Search all the forms in the analyses file.
Return all the entries whose keys match query when filter is applied to them.
Unless specified, filter defaults to string-equal."
   (let ((entries (classicist--all-matches-in-hashtable query
						      (classicist--get-all-analyses lang)
						      filter
						      ignore-case
						      no-diacritics)))
     (when entries
       (mapcar (lambda (x) (cons (car x)
			    (classicist--process-parse-result (cdr x) lang)))
	       entries))))

(defun classicist--get-all-forms (lemma lang)
  "Get all attested forms of LEMMA in LANG.
As there vould be several entries for the same lemma, this
function returns a list of lists."
  (mapcar (lambda (l) (classicist--process-lemma l lang))
	  (gethash lemma (or (classicist--get-all-lemmata lang)
			     (error "No lemmata retrieved for %s" lang)))))

(defun classicist--query-all-lemmata (query lang &optional filter ignore-case no-diacritics)
  "Search all lemmata in the lemmata file.
Return all the entries whose keys match query when filter is applied to them.
Unless specified, filter defaults to string-equal."
  (let ((entries (classicist--all-matches-in-hashtable query
						     (classicist--get-all-lemmata lang)
						     filter
						     ignore-case
						     no-diacritics)))
    (when entries
      (mapcar (lambda (l) (classicist--process-lemma (cadr l) lang))
	      entries))))

;;; Parse and look up -- a port of Perseus.pm's $do_parse / $format_analysis
;;
;; An analyses record looks like this (one line of latin-analyses.txt, for
;; the form `iacio'):
;;
;;   iacio<TAB>{34221511 9 jacio_,jacio<TAB> <TAB>pres ind act 1st sg}
;;
;; The first number of each {...} group is the BYTE OFFSET of the entry in
;; the dictionary, computed at build time by make_latin_analyses.pl through
;; a hash lookup against index_lewis.pl's key index; the second is a
;; confidence, 9 for an exact match down to 0 for "this is merely where the
;; headword would sort".  Diogenes seeks to the offset and reads a line:
;;
;;   seek $dict_fh, $dict, 0;  my $entry = <$dict_fh>;
;;
;; and so never compares the lemma against anything.  That matters, because
;; the lemma keeps Lewis & Short's j-spelling while the dictionary is
;; ordered by the i-spelling: `jacio' cannot be found by
;; `classicist--binary-search', but offset 34221511 is exact.  Searching for
;; the lemma is only the fallback for a form that would not parse at all.

(defconst classicist--analysis-group-re
  "{\\([^}]+\\)}\\(\\(?:\\[[0-9]+\\]\\)*\\)"
  "One analysis group of a record, with its supplementary offsets.
Mirrors Perl's m/{([^\\}]+)}((?:\\[\\d+\\])*)/g.  The bracketed numbers
that may follow the closing brace are further dictionary offsets --
supplementary prefix entries -- and are captured, not discarded.")

(defconst classicist--analysis-fields-re
  "\\`\\([0-9]+\\) \\([0-9]\\) \\([^\t]*\\)\t\\([^\t]*\\)\t\\(.*\\)\\'"
  "The fields inside one analysis: OFFSET CONF LEMMA<TAB>TRANS<TAB>INFO.")

(defun classicist--lemma-of-field (field)
  "The lemma in FIELD, which the analyses file gives as FORM,LEMMA.

    *bria/rew^n,bria/rews   ->  bria/rews
    si_derum,sidus          ->  sidus
    sidus                   ->  sidus

The form comes first, carrying the vowel quantities the key has not got, and
the lemma second.  `classicist--process-parse-result' has always split it this
way; the record parser did not, so the analysis header showed both joined by
the comma -- and then asked the dictionary for that, which no dictionary has as
a headword.

Where there is no comma the field IS the lemma, so nothing is lost by asking.
Where there are several, the second is taken and the rest left: a lemma may
carry a comma of its own, as `a)mfi/,peri/-pla/zw' does for a pair of
prefixes, and guessing which comma means what is beyond a display function."
  (let ((parts (split-string (or field "") "," t "[ \t]+")))
    (cond ((null parts) (or field ""))
          ((cdr parts) (cadr parts))
          (t (car parts)))))

(defun classicist--munge-ls-lemma (lemma lang)
  "Render a raw lemma from the analyses file for display.
Mirrors Perl's $munge_ls_lemma for Latin -- the vowel-quantity markers
become combining diacritics and a trailing homograph numeral is set off
by a space -- and beta-code conversion for Greek."
  (if (string= lang "greek")
      (classicist--perseus-ensure-utf8 lemma lang)
    (diogenes--replace-regexes-in-string
	(classicist--perseus-ensure-utf8
	 (replace-regexp-in-string "#?\\([0-9]\\)\\'" " \\1" lemma)
	 lang)
      ("&lt;" "<")
      ("&gt;" ">"))))

(defun classicist--parse-analyses-record (encoded-str lang)
  "Parse the raw analyses record in ENCODED-STR.
Returns a plist (:analyses ANALYSES :suppl OFFSETS), where each analysis
is itself a plist

  (:offset N :conf N :lemma RAW :display SHOWN :trans TRANS :info INFO)

in the order the record gives them.  Nothing is dropped and nothing is
merged; grouping is `classicist--analyses-dicts''s job.

`classicist-latin-analysis-corrections' is applied here, keyed by the form
the record itself is filed under, so every caller of a parse gets the same
corrected morphology -- the analysis header, the entries chosen, and the
lemma a hand-picked dictionary is asked about alike."
  (let* ((str (decode-coding-string encoded-str 'utf-8))
	 (body (or (cadr (diogenes--split-once "\t+" str)) ""))
	 (pos 0)
	 analyses suppl)
    (while (string-match classicist--analysis-group-re body pos)
      ;; Both captured here, before anything that could clobber the match
      ;; data of BODY: the loop below reads EXTRA after `:display' has run.
      (let ((group (match-string 1 body))
	    (extra (or (match-string 2 body) "")))
	(setq pos (match-end 0))
	(if (not (string-match classicist--analysis-fields-re group))
	    (message "Diogenes: bad analysis: %s" group)
	  ;; EVERY field is read before anything else is called.  The plist was
	  ;; built inline, and `:display' -- which is
	  ;; `classicist--munge-ls-lemma', and so `replace-regexp-in-string' --
	  ;; was evaluated before `:trans' and `:info' read groups 4 and 5.
	  ;; Match data is global: by then it belonged to munge's own regexps,
	  ;; those groups were nil, and `string-trim' was handed nil.  A latent
	  ;; fault for as long as the code has existed, waiting for an
	  ;; implementation that leaves fewer groups behind.
	  ;; The five reads come first and NOTHING is called between them --
	  ;; not even `string-trim', which is regexps like everything else and
	  ;; clobbered group 5 for the `info' below it when the trimming was
	  ;; done inline.  `let' binds in order, so `string-trim' on group 4
	  ;; ran before group 5 was ever read.  The trimming and the numbers
	  ;; happen in the second `let', where there is nothing left to lose.
	  (let* ((raw (list (match-string 1 group)
			    (match-string 2 group)
			    (match-string 3 group)
			    (match-string 4 group)
			    (match-string 5 group)))
		 (offset (string-to-number (nth 0 raw)))
		 (conf (string-to-number (nth 1 raw)))
		 (lemma (nth 2 raw))
		 (trans (string-trim (or (nth 3 raw) "")))
		 (info (string-trim (or (nth 4 raw) ""))))
	    (push (list :offset offset
			:conf conf
			:lemma lemma
			:display (classicist--munge-ls-lemma
				  (classicist--lemma-of-field lemma) lang)
			:trans trans
			:info info)
		  analyses)))
	(let ((p 0))
	  (while (string-match "\\[\\([0-9]+\\)\\]" extra p)
	    (push (string-to-number (match-string 1 extra)) suppl)
	    (setq p (match-end 0))))))
    (list :analyses (classicist--correct-analyses
                     (car (diogenes--split-once "\t+" str))
                     (nreverse analyses)
                     lang)
	  :suppl (delete-dups (nreverse suppl)))))

(defun classicist--analyses-dicts (record)
  "Return the entries to show for RECORD, as an alist of (OFFSET . CONF).
Offsets keep their first-seen order and occur only once; CONF is the LOWEST
confidence among the analyses pointing there.  Perl SUMS them
\(`$conf{$dict} += $conf'), which silently clears the caveat thresholds
whenever a doubtful headword is reached by several analyses at once: the
three analyses of `retemptare' are each recorded at 2, and 2+2+2 is 6, so
upstream prints no warning about an entry it knows to be a guess.  Three
uncertain analyses are not one certain one.  Supplementary offsets are
appended with a CONF of -1 unless they already occur among the analyses."
  (let (dicts)
    (dolist (a (plist-get record :analyses))
      (let* ((offset (plist-get a :offset))
	     (cell (assq offset dicts)))
	(if cell
	    (setcdr cell (min (cdr cell) (plist-get a :conf)))
	  (push (cons offset (plist-get a :conf)) dicts))))
    (setq dicts (nreverse dicts))
    (dolist (offset (plist-get record :suppl))
      (unless (assq offset dicts)
	(setq dicts (nconc dicts (list (cons offset -1))))))
    dicts))

(defun classicist--analysis-caveat (conf)
  "The note to print above an entry whose summed confidence is CONF.
Diogenes' own wording."
  (cond ((= conf -2)
	 "(Headword found by assimilating the prefix of the lemma.)")
	((= conf -1) "Supplementary prefix entry:")
	((= conf 0) "(NB. Could not find dictionary headword; \
this is around the spot it should appear.)")
	((<= conf 2) "(NB. This dictionary headword is a guess.)")))

(defun classicist--lookup-append-entry (xml-bytes start end &optional note)
  "Append the entry in XML-BYTES to the current lookup buffer.
The body of `classicist-lookup-next' minus the reading, plus an optional
NOTE above the entry.  Stacks the several entries of one analysis the way
the application does."
  (let* ((xml (decode-coding-string xml-bytes 'utf-8))
	 (formatted (classicist--dict-parse-xml xml start end))
	 (inhibit-read-only t))
    (setq classicist--lookup-bufend (max classicist--lookup-bufend end))
    (goto-char (point-max))
    (let ((beg (copy-marker (point) nil))
	  (fin (copy-marker (point) t)))
      (classicist--lookup-print-separator)
      (when note
	(insert (propertize (concat note "\n\n") 'font-lock-face 'italic)))
      (let ((entry-start (point)))
	(if formatted
	    (classicist--lookup-insert-and-format formatted)
	  (classicist--lookup-insert-xml xml start end (current-buffer)))
	(classicist--lookup-insert-entry-links classicist--lookup-lang entry-start))
      (classicist--lookup-mark-entry beg fin start end))))

(defun classicist--lookup-insert-at-top (text)
  "Insert TEXT at the top of the current lookup buffer."
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (point-min))
      (insert text))))

(defun classicist--format-analysis-header (query lang record)
  "The analysis header for QUERY, as the application prints it."
  (let ((analyses (plist-get record :analyses)))
    (cl-labels ((line (a)
		  (concat (plist-get a :display)
			  (let ((trans (plist-get a :trans)))
			    (if (string-blank-p trans)
				""
			      (format " (%s)" trans)))
			  ": " (plist-get a :info))))
      (concat
       (propertize (format "Perseus analys%s of %s:\n\n"
			   (if (= 1 (length analyses)) "is" "es")
			   (if (string= lang "greek")
			       (classicist--perseus-ensure-utf8 query lang)
			     query))
		   'font-lock-face 'shr-h2)
       (if (= 1 (length analyses))
	   (concat (line (car analyses)) "\n")
	 (cl-loop for a in analyses
		  for i from 1
		  concat (format "%2d. %s\n" i (line a))))
       "\n"))))

(defcustom classicist-lookup-expand-homographs t
  "Whether a guessed dictionary entry is shown together with its homographs.
When the offset recorded for a lemma is a guess -- confidence 2 or less --
the entry it names is as likely as not the wrong one of a numbered set, and
the others are worth seeing.

`index_lewis.pl' indexes each Lewis & Short key five ways and keeps the
first claim on each spelling:

    print \"$basic_key $i\\n\" unless $seen{$basic_key}++;

so of the two entries keyed `re^tento1' and `re^tento2' only the first ever
answers to the letters-only spelling `retento'.  Morpheus writes the
compound as `re-tento', which matches no key at all, so
`make_latin_analyses.pl' falls through to its last resort --

    unless ($ls{$real_lemma}) { $conf = 2; $real_lemma =~ s/[^a-zA-Z]//g }

-- and records the offset of `re^tento1', the frequentative of `retineo',
for a form belonging to `re^tento2', to attempt again.  Parsing
`retemptare' then shows the wrong entry with no hint that anything is
amiss.  Showing both leaves the reader to pick, which is the best that can
be done without an index that distinguishes them."
  :type 'boolean
  :group 'diogenes)

(defun classicist--dict-basic-key (entry)
  "The letters of ENTRY's key, downcased: `re^tento2' gives `retento'.
The spelling `index_lewis.pl' reduces a key to for its coarsest index, and
the only one a homograph number does not distinguish."
  (when (string-match "key\\s-*=\\s-*\"\\([^\"]*\\)\"" entry)
    (downcase (diogenes--ascii-alpha-only (match-string 1 entry)))))

(defun classicist--dict-homograph-run (offset lang &optional file limit)
  "The entries around OFFSET that share its headword, as (START END BYTES).
Homographs are numbered forms of one headword -- `re^tento1', `re^tento2'
-- and so are always neighbours in the file: this walks outwards from
OFFSET while the letters-only key still matches, at most LIMIT entries in
each direction (six by default).  Returns them in file order, OFFSET's own
entry among them."
  (let* ((dict (or file (diogenes--dict-file lang)))
	 (limit (or limit 6))
	 (here (classicist--get-dict-line dict offset)))
    (if (not (car here))
	nil
      ;; `classicist--get-dict-line' returns (BYTES START END); a run entry is
      ;; (START END BYTES).
      (let* ((key (classicist--dict-basic-key (car here)))
	     (self (list (nth 1 here) (nth 2 here) (nth 0 here)))
	     (before nil)
	     (after nil))
	(when key
	  ;; Leftwards from the START of the leftmost entry so far.  Stepping
	  ;; from its END would land inside the entry itself, which of course
	  ;; still has the same key, and the entry would be collected again and
	  ;; again until LIMIT stopped it.
	  (let ((pos (1- (nth 0 self)))
		(n 0))
	    (while (and (< n limit) (> pos 0))
	      (let ((line (classicist--get-dict-line dict pos)))
		(if (and (car line)
			 (equal key (classicist--dict-basic-key (car line)))
			 (< (nth 1 line) (nth 0 (or (car before) self))))
		    (progn (push (list (nth 1 line) (nth 2 line) (nth 0 line))
				 before)
			   (setq pos (1- (nth 1 line))
				 n (1+ n)))
		  (setq n limit)))))
	  ;; Rightwards from the END of the rightmost entry so far.
	  (let ((pos (1+ (nth 1 self)))
		(n 0))
	    (while (< n limit)
	      (let ((line (classicist--get-dict-line dict pos)))
		(if (and (car line)
			 (equal key (classicist--dict-basic-key (car line)))
			 (> (nth 1 line)
			    (nth 0 (or (car (last after)) self))))
		    (setq after (nconc after
				       (list (list (nth 1 line) (nth 2 line)
						   (nth 0 line))))
			  pos (1+ (nth 2 line))
			  n (1+ n))
		  (setq n limit))))))
	(append before (list self) after)))))

(defun classicist--dict-entry-hyphenated-p (entry)
  "Whether ENTRY's printed headword contains a hyphen.
Lewis & Short prints the compound as `rĕ-tento' and the frequentative as
`rĕtento', a distinction its keys drop but its `orth_orig' keeps -- the
same distinction Morpheus makes by writing the lemma `re-tento'."
  (and (string-match "orth_orig\\s-*=\\s-*\"\\([^\"]*\\)\"" entry)
       (string-search "-" (match-string 1 entry))
       t))

(defun classicist--dict-exact-offset (word lang &optional file)
  "The offset of the entry whose key is WORD, or nil if there is none.
Unlike `classicist--lookup-dict\=', a miss is a miss: nothing is displayed and
no nearest entry offered, so this can be used to ask the dictionary whether
a spelling exists at all."
  (seq-let (_bytes start _end exact-hit)
      (classicist--binary-search
       (or file (diogenes--dict-file lang))
       (if (string= lang "latin")
	   #'classicist--latin-sort-function
	 #'classicist--ascii-sort-function)
       #'classicist--xml-key-fn
       word)
    (and exact-hit start)))

(defun classicist--assimilated-offset (lemma lang &optional file)
  "The offset of the entry for the hyphenated LEMMA, or nil.
The first of `classicist--latin-assimilations\=' that the dictionary has a key
for.  See `classicist-latin-assimilate-prefixes\='."
  (when (and classicist-latin-assimilate-prefixes
	     (string= lang "latin")
	     (string-search "-" lemma))
    (cl-loop for candidate in (classicist--latin-assimilations lemma)
	     thereis (classicist--dict-exact-offset candidate lang file))))

(defun classicist--expand-homographs (offset conf lemma lang &optional file)
  "The homographs of the entry at OFFSET, each carrying CONF.
LEMMA settles their order: where it is hyphenated, an entry whose printed
headword is hyphenated comes first, that being the same distinction between
a compound and a simple verb."
  (let* ((run (classicist--dict-homograph-run offset lang file))
	 (hyphenated (and lemma (string-search "-" lemma))))
    (cond
     ((< (length run) 2) (list (cons offset conf)))
     (t (let ((offsets (mapcar #'car run)))
	  (when hyphenated
	    (setq offsets
		  (append
		   (cl-loop for (start _end bytes) in run
			    when (classicist--dict-entry-hyphenated-p bytes)
			    collect start)
		   (cl-loop for (start _end bytes) in run
			    unless (classicist--dict-entry-hyphenated-p bytes)
			    collect start))))
	  (mapcar (lambda (o) (cons o conf))
		  (delete-dups offsets)))))))

(defun classicist--expand-uncertain-dicts (record dicts lang &optional file)
  "Add the homographs of any guessed entry in DICTS, an alist of (OFFSET . CONF).
An entry whose confidence is 2 or less was reached by stripping the lemma
down to its letters, which cannot tell numbered homographs apart, so its
neighbours are included too.  Where the lemma is hyphenated, an entry whose
printed headword is hyphenated is shown first, that being the same
distinction; otherwise file order is kept.  Governed by
`classicist-lookup-expand-homographs'."
  (if (not classicist-lookup-expand-homographs)
      dicts
    (cl-loop
     for (offset . conf) in dicts
     append
     (if (or (< conf 0) (> conf 2))
	 (list (cons offset conf))
       (let* ((lemma (cl-loop for a in (plist-get record :analyses)
			      thereis (and (= offset (plist-get a :offset))
					   (plist-get a :lemma))))
	      (assimilated (and lemma
				(classicist--assimilated-offset lemma lang file))))
	 (if assimilated
	     ;; The dictionary has a key for the assimilated spelling, so the
	     ;; guessed offset can be replaced outright rather than hedged.
	     (list (cons assimilated -2))
	   (classicist--expand-homographs offset conf lemma lang file)))))))

(defun classicist--show-analysis-entries (dicts lang &optional file)
  "Show the entries named by DICTS, an alist of (OFFSET . CONF).
The first goes into a fresh lookup buffer and the rest are appended to
it, as `$format_analysis' stacks them.  Returns that buffer."
  (unless dicts (error "No dictionary entries to show"))
  (let ((dict (or file (diogenes--dict-file lang)))
	(buffer nil))
    (cl-loop for (offset . conf) in dicts
	     for note = (classicist--analysis-caveat conf)
	     do (seq-let (xml-bytes start end)
		    (classicist--get-dict-line dict offset)
		  (cond
		   ((not xml-bytes)
		    (message "Diogenes: no dictionary entry at offset %d"
			     offset))
		   ((not buffer)
		    (setq buffer (classicist--show-dict-entry
				  xml-bytes start end lang file))
		    (when note
		      (with-current-buffer buffer
			(classicist--lookup-insert-at-top
			 (propertize (concat note "\n\n")
				     'font-lock-face 'italic)))))
		   (t
		    (with-current-buffer buffer
		      (classicist--lookup-append-entry
		       xml-bytes start end note))))))
    (or buffer (error "None of the offsets could be read"))))

(defun classicist--try-parse (word lang)
  "Look WORD up in LANG's analyses file; return the raw record or nil.
`$try_parse': the .idt index gives the byte range of the bucket for the
first three characters of WORD and the binary search is confined to it.
WORD is used AS GIVEN -- make_index.pl keys the buckets on the raw prefix
and the file is LC_ALL=C sorted, so a query downcased before the key is
computed looks in the wrong bucket and can never match `Itys'."
  (let* ((analyses-file (file-name-concat (diogenes--perseus-path)
					  (concat lang "-analyses.txt")))
	 (index (classicist--get-analyses-index lang))
	 (key (if (> (length word) 3) (substring word 0 3) word))
	 (start (let ((s (cdr (assoc key (plist-get index :index-start)))))
		  (if s (- s 2) 0)))
	 (end (or (cdr (assoc key (plist-get index :index-end)))
		  (plist-get index :index-max)))
	 (result (classicist--binary-search analyses-file
					  #'classicist--c-sort-function
					  #'classicist--tab-key-fn
					  word
					  start end)))
    (and (nth 3 result) (car result))))

(defun classicist--do-parse (word lang)
  "Return the raw analyses record for WORD in LANG, or nil.
`$do_parse': the form is tried as it stands and a capitalised Latin form
is then retried in lower case -- Diogenes' \"Fixed parsing of capitalized
Latin words\".  The reshuffling of diacritics after a beta-code asterisk
that $do_parse also does for Greek capitals is not attempted here.

Beyond the application, a Latin form is also tried as a contraction and
without its diacritics (see `classicist--latin-parse-candidates') and with j
and i exchanged (see `classicist--latin-form-variants')."
  (let* ((word (diogenes--beta-normalize-gravis
                (diogenes--greek-ensure-beta word)))
         (variants
          (if (string= lang "latin")
              (cl-loop for base in (classicist--latin-parse-candidates word)
                       append (classicist--latin-form-variants base))
            ;; Greek: the form as it stands, and then without the accent an
            ;; ENCLITIC put on it.  A proparoxytone takes an extra acute on its
            ;; ultima when an enclitic follows, so the text prints
            ;; `*bria/rew/n' where the analyses file has `*bria/rewn' -- and the
            ;; search then looked for a key that cannot exist, landed on
            ;; whatever sorted next to it, and showed that entry: `Briareon'
            ;; was answered with `Briakchos'.
            ;;
            ;; The word as written stays first, so nothing that parses today
            ;; stops parsing.
            (classicist--greek-parse-candidates word))))
    (or
     (cl-loop for variant in (delete-dups variants)
              thereis (or (classicist--try-parse variant lang)
                          (and (string-match-p "[[:upper:]]" variant)
                               (classicist--try-parse (downcase variant) lang))))
     ;; THE WORDLIST'S OWN SPELLING, found by letting the accents go.
     ;;
     ;; An editor's accentuation is not always the file's: Ross prints
     ;; `mu=on' for the participle of `mu/w' where the file has `mu/on'.
     ;; Every variant above is an exact lookup, and the KEYS keep their
     ;; accents, so no amount of stripping the query can reach a key spelled
     ;; otherwise -- `mu=on' found nothing and the caller fell back on
     ;; showing whatever sorted next to it, `mu?omaxi/a', a battle of mice.
     ;;
     ;; So the form is looked for with diacritics ignored on BOTH sides,
     ;; which is what `diogenes-parse-greek' does and why that command found
     ;; it.  What comes back is the file's own key, and THAT is parsed in the
     ;; ordinary way -- so the record is built by the usual code, with the
     ;; usual offsets and confidences, and nothing here has to know how an
     ;; analysis is shaped.
     ;;
     ;; THE ACCENT MOVED, tried a few cheap ways before the dear one.
     ;;
     ;; `classicist--try-parse' costs almost nothing: the .idt index gives the
     ;; bucket for the first three characters and the binary search stays
     ;; inside it.  `classicist--parse-all' costs a great deal: the whole
     ;; analyses file -- nine hundred thousand keys -- read into a hashtable,
     ;; and then every key of it transformed to build a second table without
     ;; diacritics.  Seconds, the first time in a session, for one word.
     ;;
     ;; A Greek word carries ONE accent, and the spelling sought differs from
     ;; the spelling given only in where that accent sits and which it is.  So
     ;; the accent is put on each vowel in turn, acute, grave and circumflex,
     ;; and each spelling looked up exactly: six lookups for `muon', twelve
     ;; for a long word, and every one of them a binary search in one bucket.
     (and (string= lang "greek")
          (cl-loop for candidate in (classicist--greek-accent-variants word)
                   thereis (classicist--try-parse candidate lang)))
     ;; AND ONLY THEN THE WHOLE FILE, for a form the accents alone do not
     ;; explain -- a breathing misread, an iota subscript dropped.  Dear, but
     ;; once per session, and better than not finding the word.
     (and (string= lang "greek")
          (let ((found (ignore-errors
                         (classicist--parse-all word lang nil t t))))
            (cl-loop for (key . _) in found
                     thereis (and (stringp key)
                                  (classicist--try-parse key lang))))))))

(defun classicist--choose-analysis (record dicts word)
  "Ask which lemma of RECORD to show; return its (OFFSET . CONF) alone.
Used when `classicist-lookup-show-all-entries' is nil."
  (let* ((alist (cl-loop
		 with seen = nil
		 for a in (plist-get record :analyses)
		 for label = (format "%s (%s)"
				     (plist-get a :display)
				     (if (string-blank-p (plist-get a :trans))
					 "No translation available"
				       (plist-get a :trans)))
		 unless (member label seen)
		 collect (progn (push label seen)
				(list label
				      (plist-get a :offset)
				      (concat "\t" (plist-get a :info))))))
	 (completion-extra-properties
	  '(:annotation-function
	    (lambda (s) (caddr (assoc s minibuffer-completion-table)))))
	 (offset (if (= 1 (length alist))
		     (cadr (car alist))
		   (cadr (assoc (completing-read
				 (format "Choose a lemma for %s: " word)
				 alist)
				alist)))))
    (if offset
	(list (or (assq offset dicts) (cons offset 9)))
      dicts)))

(defcustom classicist-greek-extra-lemmata nil
  "Greek forms the wordlists have no analysis for, and the headword to show.
An alist of (FORM . HEADWORD), as `classicist-latin-extra-lemmata\=' is for Latin:

    (setq classicist-greek-extra-lemmata
          \='((\"οὑτοσί\" . \"οὗτος\")
            (\"ταὐτόν\"  . \"αὐτός\")))

Consulted only when the analyses file has nothing at all for the form, so it
adds and never overrides.  Accents and breathings are compared as the rest of
the Greek lookup compares them, so an entry written unaccented answers for the
accented form.

Deictic and crasis forms are what this is mostly for: the wordlists carry the
plain word and not `οὑτοσί\=', and Morpheus does not always oblige."
  :type '(alist :key-type (string :tag "Form")
                :value-type (string :tag "Headword"))
  :group 'diogenes)

(defcustom classicist-greek-analysis-corrections nil
  "Greek analyses the shipped data gets wrong, and what to say instead.
Keyed by the form, as `classicist-latin-analysis-corrections\=' is for Latin, and
taking the same three keys:

  :info STRING     -- the morphology to print instead
  :lemma STRING    -- the headword, and the entry the dictionary keys open
  :add ENTRIES     -- ((LEMMA . INFO) ...), readings to show as well

    (setq classicist-greek-analysis-corrections
          \='((\"ᾖ\" :info \"pres subj act 3rd sg\")))

The Greek data is wrong more often than the Latin, not less: Morpheus knows
less of it, and the LSJ keys some headwords differently from the form Morpheus
gives.  A reader who has worked out what a form actually is should be able to
record it."
  :type '(alist :key-type (string :tag "Form") :value-type plist)
  :group 'diogenes)

(defun classicist--extra-lemmata-for (lang)
  "The extra-lemmata table for LANG."
  (if (string= lang "greek")
      classicist-greek-extra-lemmata
    classicist-latin-extra-lemmata))

(defun classicist--analysis-corrections-for (lang)
  "The corrections table for LANG."
  (if (string= lang "greek")
      classicist-greek-analysis-corrections
    classicist-latin-analysis-corrections))

(defun classicist--extra-lemma (word lang)
  "The headword the extra-lemmata table for LANG gives WORD, or nil.
Latin tries every spelling variant, so an entry written with v and j answers
for the form written with u and i; Greek compares the form as it stands and
again stripped of its accents, so an entry written unaccented answers for the
accented word."
  (let ((table (classicist--extra-lemmata-for lang)))
    (when table
      (cl-loop for variant in (if (string= lang "greek")
                                  (list word (diogenes--ascii-alpha-only word))
                                (classicist--latin-form-variants word))
               thereis (cdr (assoc-string variant table t))))))

(defun classicist--latin-extra-lemma (word)
  "The headword `classicist-latin-extra-lemmata\=' gives for WORD, or nil.
Every spelling variant of WORD is tried, so an entry written with v and j
also answers for the form written with u and i."
  (cl-loop for variant in (classicist--latin-form-variants word)
	   thereis (cdr (assoc-string variant
				    classicist-latin-extra-lemmata t))))

(defun classicist--analysis-correction (form lang)
  "The correction plist for FORM in LANG, or nil.
The Greek and Latin tables are read the same way; only the table differs."
  (let ((table (classicist--analysis-corrections-for lang)))
    (and table
         (cl-loop for variant in (if (string= lang "greek")
                                     (list form (diogenes--ascii-alpha-only form))
                                   (classicist--latin-form-variants form))
                  thereis (cdr (assoc-string variant table t))))))

(defun classicist--latin-analysis-correction (form)
  "The correction plist `classicist-latin-analysis-corrections' gives FORM.
Every spelling variant is tried, so an entry written with v and j answers
for the form written with u and i."
  (and classicist-latin-analysis-corrections
       (cl-loop for variant in (classicist--latin-form-variants form)
                thereis (cdr (assoc-string
                              variant classicist-latin-analysis-corrections t)))))

(defun classicist--mark-correction (info)
  "INFO marked as corrected, if `classicist-latin-mark-corrections' says so."
  (if classicist-latin-mark-corrections
      (concat info " [corr.]")
    info))

(defun classicist--corrected-info (info spec)
  "INFO as SPEC would have it: SPEC itself, its alist entry, or INFO."
  (cond ((stringp spec) spec)
        ((consp spec) (or (cdr (assoc-string info spec t)) info))
        (t info)))

(defun classicist--added-analysis (lemma info model lang)
  "An analysis of LEMMA reading INFO, shaped like the file's own.
LEMMA nil takes the lemma and the byte offset of MODEL, the analysis the
file gave, so a missing reading of the same word costs no lookup and lands
on the same entry.  A LEMMA given is resolved against the dictionary's own
keys, as `classicist--morpheus-analyses' resolves one: found, it carries that
offset and a confidence of 5; not found, 0, which prints the caveat about
the headword being a guess."
  (if (null lemma)
      (list :offset (or (plist-get model :offset) 0)
            :conf (or (plist-get model :conf) 5)
            :lemma (plist-get model :lemma)
            :display (plist-get model :display)
            :trans ""
            :info (classicist--mark-correction info))
    (let ((offset (classicist--dict-exact-offset
                   (diogenes--ascii-alpha-only lemma) lang)))
      (list :offset (or offset 0)
            :conf (if offset 5 0)
            :lemma lemma
            :display (classicist--munge-ls-lemma lemma lang)
            :trans ""
            :info (classicist--mark-correction info)))))

(defun classicist--correct-analyses (form analyses lang)
  "ANALYSES of FORM, with `classicist-latin-analysis-corrections' applied.
Returns ANALYSES unchanged when there is no entry for FORM, which is the
usual case and costs one `assoc-string' per lookup.  Either language: the
table is `classicist-latin-analysis-corrections' or
`classicist-greek-analysis-corrections' according to LANG."
  (let ((spec (classicist--analysis-correction form lang)))
    (if (null spec)
        analyses
      (let ((info-spec (plist-get spec :info))
            (lemma-spec (plist-get spec :lemma))
            (model (car analyses)))
        (append
         (mapcar (lambda (analysis)
                   (let* ((old (plist-get analysis :info))
                          (new (classicist--corrected-info old info-spec))
                          (analysis (if (equal old new)
                                        analysis
                                      (plist-put (copy-sequence analysis) :info
                                                 (classicist--mark-correction new)))))
                     ;; A corrected LEMMA is the headword the reader has
                     ;; supplied, so its ENTRY is found the way a Morpheus
                     ;; lemma's is -- by name among the dictionary's keys, and
                     ;; under the assimilated spellings if it is a compound.
                     ;; See `classicist--morpheus-analyses'.
                     ;;
                     ;; Three fields and not one.  `:display' is what is
                     ;; printed, `:lemma' what the assimilation machinery
                     ;; reads, and `:offset' where the entry begins.  Setting
                     ;; only `:lemma' left the wrong headword on the screen;
                     ;; setting the offset to 0 opened byte 0 of the file,
                     ;; which is the entry for the letter A.
                     (if (not lemma-spec)
                         analysis
                       (let* ((plain (diogenes--ascii-alpha-only lemma-spec))
                              ;; A correction must not signal: the dictionary
                              ;; may not be searchable at all -- `diogenes-path'
                              ;; unset, the file absent -- and a reader who has
                              ;; named a better headword should still see it,
                              ;; with the caveat that its entry is a guess.
                              (offset
                               (ignore-errors
                                 (or (classicist--dict-exact-offset plain lang)
                                     (classicist--assimilated-offset lemma-spec
                                                                   lang))))
                              (shown (classicist--mark-correction lemma-spec))
                              (copy (copy-sequence analysis)))
                         (setq copy (plist-put copy :lemma lemma-spec))
                         (setq copy (plist-put copy :display shown))
                         ;; A confidence of 5 where the entry was found, and 0
                         ;; where it was not -- which prints the caveat about
                         ;; the headword being a guess rather than pretending
                         ;; to an entry it has not got.
                         (setq copy (plist-put copy :conf (if offset 5 0)))
                         (plist-put copy :offset
                                    (or offset
                                        (plist-get analysis :offset)))))))
                 analyses)
         (cl-loop for (lemma . info) in (plist-get spec :add)
                  collect (classicist--added-analysis lemma info model lang)))))))


;;; Morpheus as a fallback
;;
;; Diogenes' analyses are a batch run of Morpheus over wordlists harvested
;; from the corpora it indexes, so a form those wordlists never saw is not
;; misspelt but absent -- `transilire', `illidant', `aedium', while their
;; sibling forms are all present.  Morpheus itself generates paradigms from
;; stems and knows them.  If a build of it is to hand, asking it is better
;; than falling back on a search for a form that is nobody's headword.
;;
;; Second, and not first.  The shipped data has two things Morpheus does not:
;; the BYTE OFFSET of the dictionary entry, resolved at build time through
;; `index_lewis.pl''s key index, and the short gloss.  A Morpheus lemma is a
;; string, so its entry has to be found by name -- which is exactly the
;; unreliable path.  Diogenes' own analyses are therefore always preferred,
;; and Morpheus asked only where they have nothing.
;;
;; It also emits the same hyphenated compounds the shipped data does --
;; `in-mitto', `con-pello', flagged `raw_preverb' -- so its lemmas go through
;; `classicist--assimilated-offset' like any other.  And it is fast: 2.7 ms for
;; one word, startup included, so a process per lookup is simpler than
;; keeping one alive and costs nothing measurable.

(defcustom classicist-morpheus-directory nil
  "Directory of a built Morpheus, or nil not to use one.
Must hold `bin/cruncher' and `stemlib/', which is how the tree is laid out
by

    git clone https://github.com/VictorSousa92/morpheus
    cd morpheus/src && make CC=\"gcc -std=gnu17 -fpermissive\" && make install
    cd ../stemlib/Latin && env PATH=\"$PWD/../../bin:$PATH\" MORPHLIB=\"$PWD/..\" make

That fork is the one this was tested against, and the recommended one: its
stems are more complete, so it answers for forms another build declines.

Nothing here requires it.  Any Morpheus laid out the same way is run the
same way -- the cruncher reading forms from stdin, `-L' for Latin, MORPHLIB
naming `stemlib' -- and two things have to hold of whichever is used.  Its
output must carry the `<NL>...</NL>' wrappers the parser reads (see
`classicist--morpheus-analysis-re'), and it must spell a lemma as Lewis & Short
keys it, since Morpheus has no notion of where an entry sits in a file and
the lemma is resolved against the dictionary's own keys.  Beyond the initial
`j' that `classicist-latin-fold-letters' folds and the prefixes
`classicist-latin-assimilate-prefixes' assimilates, a lemma spelt otherwise
gets a confidence of 0 and the caveat about the headword being a guess,
rather than a wrong entry.

Consulted only when a form will not parse from the shipped data, so an
installation without this set behaves as before."
  :type '(choice (const :tag "Do not use Morpheus" nil) directory)
  :group 'diogenes)

(defcustom classicist-morpheus-timeout 10
  "Seconds to wait for Morpheus before giving up on a form."
  :type 'natnum
  :group 'diogenes)

(defun classicist-morpheus-available-p ()
  "Whether `classicist-morpheus-directory' holds a usable Morpheus."
  (and classicist-morpheus-directory
       (let ((bin (expand-file-name "bin/cruncher"
				    classicist-morpheus-directory))
	     (lib (expand-file-name "stemlib" classicist-morpheus-directory)))
	 (and (file-executable-p bin) (file-directory-p lib)))))

(defun classicist--morpheus-run (word lang)
  "Ask Morpheus about WORD in LANG; return its raw output, or nil.
The cruncher reads forms from stdin, one per line, and wants beta code for
Greek -- which is what it gets, `classicist--do-parse' having converted the
form already.  MORPHLIB must name the `stemlib' directory itself, not its
parent: the cruncher appends the language to it."
  (when (classicist-morpheus-available-p)
    (let* ((dir (file-name-as-directory
		 (expand-file-name classicist-morpheus-directory)))
	   (process-environment
	    (cons (concat "MORPHLIB=" dir "stemlib") process-environment))
	   (args (append (when (string= lang "latin") '("-L"))
			 nil)))
      (with-temp-buffer
	(let ((exit (condition-case err
			(apply #'call-process-region
			       (concat word "\n") nil
			       (concat dir "bin/cruncher")
			       nil t nil args)
		      (error (message "Morpheus: %s" (error-message-string err))
			     nil))))
	  (when (and exit (or (eq exit 0) (integerp exit)))
	    (buffer-string)))))))

(defconst classicist--morpheus-analysis-re
  "<NL>\\([^<]*\\)</NL>"
  "One analysis in Morpheus' output.
The cruncher answers with the form, then its analyses run together:

  <NL>V transi^li_re,transilio  pres inf act\t\t\tconj4,ire_vb</NL>

which is part of speech, then form and lemma, then the morphology, then
dialect and stem-class fields separated by tabs.")

(defcustom classicist-morpheus-lemma-markers
  '(("pl" . "lemma listed under the plural")
    ("dual" . "lemma listed under the dual")
    ("indecl" . "indeclinable"))
  "What Morpheus\=' lemma markers mean, as (MARKER . WHAT-TO-SAY).
Morpheus spells some lemmata with a marker after a hyphen -- `*bria/rews-pl\=' is
Briareus, listed under the plural -- and the marker is no part of the name: left
on, it is asked of the dictionary, matches no headword, and the search falls to
whatever sorts first.

So it is taken off the lemma and said in words beside the morphology.  A marker
not listed here is shown as it stands, which is better than dropping it and
better than pretending to translate it."
  :type '(alist :key-type (string :tag "Marker")
                :value-type (string :tag "What to say"))
  :group 'diogenes)

(defun classicist--morpheus-lemma-marker (lemma)
  "The marker at the end of LEMMA, or nil.
Only what `classicist-morpheus-lemma-markers\=' names.  A hyphen in a Morpheus
lemma is usually a COMPOUND -- `a)mfi/-pla/ssw\=' is one word -- so a rule that
took whatever followed the last hyphen would cut real lemmata in half wherever
the second element happened to carry no accent.  Nothing comes off unless it is
known to be a marker."
  (when (and lemma (string-match-p "-" lemma))
    (let ((tail (car (last (split-string lemma "-")))))
      (and (assoc tail classicist-morpheus-lemma-markers) tail))))

(defun classicist--morpheus-parse-output (output lang)
  "Turn Morpheus' OUTPUT into analyses shaped like an analyses record's.
Each is a plist (:offset :conf :lemma :display :trans :info), the same
shape `classicist--parse-analyses-record' produces, so that everything
downstream -- the stacking, the notes, the homograph sweep, navigation --
works on it unchanged.

:offset is filled in later by `classicist--morpheus-analyses': the lemma has
to be resolved against the dictionary's own keys, Morpheus having no notion
of where an entry sits in a file.  :trans is empty, Morpheus giving no
glosses."
  (let ((pos 0) out)
    (while (string-match classicist--morpheus-analysis-re (or output "") pos)
      (setq pos (match-end 0))
      (let* ((body (match-string 1 output))
	     (fields (split-string body "\t" nil))
	     (head (string-trim (or (car fields) "")))
	     ;; "V transi^li_re,transilio  pres inf act"
	     (parts (split-string head "[[:space:]]\\{2,\\}" t))
	     (lemma-field (string-trim (or (car parts) "")))
	     (info (string-join (cdr parts) " "))
	     ;; Drop the part-of-speech letter that opens the field.
	     (lemma-field (if (string-match "\\`[A-Z] +" lemma-field)
			      (substring lemma-field (match-end 0))
			    lemma-field))
	     ;; "form,lemma" -- the lemma is what follows the comma, as
	     ;; make_latin_analyses.pl also takes it.
	     (lemma (if (string-match "," lemma-field)
			(substring lemma-field (match-end 0))
		      lemma-field))
	     ;; And Morpheus marks some lemmata: `*bria/rews-pl' is Briareus
	     ;; listed under the plural.  The marker is no part of the name, so
	     ;; it cannot stay on a string that will be asked of a dictionary --
	     ;; `Briareos-pl' matches no headword, and the search fell to the
	     ;; dictionary's first entry with a note that it had found nothing.
	     (marker (classicist--morpheus-lemma-marker lemma))
	     (lemma (if marker
			(substring lemma 0 (- (length lemma) (length marker) 1))
		      lemma))
	     (extra (string-join
		     (seq-remove #'string-empty-p
				 (mapcar #'string-trim (cdr fields)))
		     " "))
	     ;; The marker is not discarded: that the lemma is listed under the
	     ;; plural is worth a reader's knowing, and LSJ has such headwords.
	     ;; It goes where Morpheus' other remarks go.
	     (info (if marker
		       (concat info " ("
			       (or (cdr (assoc marker
					       classicist-morpheus-lemma-markers))
				   marker)
			       ")")
		     info)))
	(when (and lemma (not (string-empty-p lemma)))
	  (push (list :offset 0
		      :conf 5
		      :lemma lemma
		      :display (classicist--munge-ls-lemma lemma lang)
		      :trans ""
		      :info (string-trim
			     (concat info (if (string-empty-p extra)
					      ""
					    (concat " [" extra "]")))))
		out))))
    (nreverse out)))

(defun classicist--morpheus-analyses (word lang)
  "Analyses of WORD from Morpheus, with their entries resolved, or nil.
A lemma is looked for among the dictionary's keys as it stands and, being
possibly a hyphenated compound, under its assimilated spellings as well.
An analysis whose lemma is found carries that offset and a confidence of 5;
one whose lemma is not carries 0, which prints the caveat about the headword
being a guess -- the morphology is worth showing either way, and it is more
than the alternative of an unrelated entry and no analysis at all."
  (let ((analyses (classicist--morpheus-parse-output
		   (classicist--morpheus-run word lang) lang)))
    (cl-loop
     for a in analyses
     for lemma = (plist-get a :lemma)
     for plain = (diogenes--ascii-alpha-only lemma)
     for offset = (or (classicist--dict-exact-offset plain lang)
		      (classicist--assimilated-offset lemma lang))
     collect (plist-put (plist-put (copy-sequence a) :offset (or offset 0))
			:conf (if offset 5 0)))))

(defun classicist--parse-and-lookup (word lang)
  "Try to parse a word by looking it up in the morphological files,
and show the entry for it in the lexica. Dispatcher function.

A port of `$do_parse' followed by `$format_analysis': every entry named
in the analyses record is fetched from the byte offset recorded there.
Only a form that will not parse falls back on searching the dictionary by
headword, exactly as the application does."
  (let* ((raw (classicist--do-parse word lang))
	 (extra (classicist--extra-lemma word lang))
	 ;; Only where the shipped data has nothing: its offsets and glosses
	 ;; are better than anything that can be recovered from a lemma.
	 (morpheus (and (not raw) (not extra)
			(classicist-morpheus-available-p)
			(classicist--morpheus-analyses word lang))))
    (if (not raw)
	(cond
	 (morpheus
	  (let* ((record (list :analyses morpheus :suppl nil))
		 (dicts (classicist--analyses-dicts record)))
	    (message "%s does not parse; analysed by Morpheus" word)
	    (let ((buffer (classicist--show-analysis-entries
			   (classicist--expand-uncertain-dicts record dicts lang)
			   lang)))
	      (when classicist-lookup-show-analysis
		(with-current-buffer buffer
		  (classicist--lookup-insert-at-top
		   (classicist--format-analysis-header word lang record))
		  (goto-char (point-min))))
	      buffer)))
	 ;; A form the wordlists never had.  The headword is known, even
	 ;; though the analysis is not, so show its entry rather than
	 ;; whatever happens to sort next to the form.
	 (extra
	  (message "%s does not parse; showing %s" word extra)
	  (classicist--lookup-dict extra lang))
	 (t
	  (message "No results for %s, trying to look it up in the dictionaries!"
		   word)
	  (classicist--lookup-dict word lang)))
      (let* ((record (classicist--parse-analyses-record raw lang))
	     (dicts (classicist--analyses-dicts record)))
	(if (null dicts)
	    (progn
	      (message "No dictionary entry for %s; searching by headword" word)
	      (classicist--lookup-dict word lang))
	  (let ((buffer (classicist--show-analysis-entries
			 (if classicist-lookup-show-all-entries
			     (classicist--expand-uncertain-dicts record dicts lang)
			   (classicist--choose-analysis record dicts word))
			 lang)))
	    (when classicist-lookup-show-analysis
	      (with-current-buffer buffer
		(classicist--lookup-insert-at-top
		 (classicist--format-analysis-header word lang record))
		(goto-char (point-min))))
	    buffer))))))

(defun classicist--add-parse-entry ()
  "Get or create an Diogenes Analysis buffer, and begin a new entry."
  ;; `morphology' and not `lookup': an analysis is not an entry, and displaying
  ;; it as one made it replace whatever entry the reader was consulting -- which
  ;; is the entry they wanted the analysis alongside.
  (classicist-display-buffer (get-buffer-create "*Diogenes Analysis*")
			    :kind 'morphology)
  (goto-char (point-max))
  (unless (eq major-mode #'classicist-analysis-mode)
    (classicist-analysis-mode))
  (unless (diogenes--first-line-p)
    (insert "\n")))

(defun classicist--parse-and-show-choose-filter (filter ignore-case no-diacritics)
  "Choose an approriate filter function for `classicist--parse-and-show'."
  (cons
   (or filter
       (let* ((functions '((?l . string-equal)
			   (?p . string-prefix-p)
			   (?s . string-suffix-p)
			   (?i . string-search)
			   (?r . string-match-p)
			   (?o . other)))
	      (filter (alist-get (read-char-from-minibuffer
				  (concat "Match (l)iterally, or as "
					  "(p)refix, "
					  "(s)uffix, "
					  "(i)nfix, "
					  "(r)egular expression,"
					  "(o)ther: ")
				  (cl-loop for l in functions
					   collect (car l)))
				 functions nil nil #'eql)))
      (cl-case filter
	((nil) #'string-equal)
	(other
	 (read-minibuffer
	  "Enter a function-object of two arguments, the query and the string: "))
	(t filter))))
   (list (cl-case ignore-case
	   ((nil) (not (y-or-n-p "Make the search case sensitive?")))
	   (ignore nil)
	   (t t))
	 (cl-case no-diacritics
	   ((nil) (not (y-or-n-p "Make the search diacritics sensitive?")))
	   (ignore nil)
	   (t t)))))


(defun classicist--assign-parse-result-to-lemmata (parse-results)
  "Loop through the result of `classicist--process-parse-result',
assigning the single results to their respective lemmata. Returns the lemmata as a list,
where each lemma is itself a list consisting of the LEMMA-NR, the LEMMA-WORD, the TRANSLATION
and the list on ANALYSES."
  (cl-loop
   with lemmata
   for (headword lemma-word lemma-nr translation analysis) in parse-results
   for existent-lemma = (assoc lemma-word lemmata)
   for entry = (cons headword analysis)
   unless existent-lemma do (push (list (or lemma-word
					    headword)
					lemma-nr
					(if (string-blank-p translation)
					    "No translation available"
					  translation)
					(list entry))
				  lemmata)
   else do (push entry (cl-fourth existent-lemma))
   finally return lemmata))

(defun classicist--format-parse-results (query lang results)
  "Process and format the results of `classicist--process-parse-result'.
Besides the fontification, it also checks for duplicate lemma
entries and orders them accordingly."
  (let ((lemmata (classicist--assign-parse-result-to-lemmata results)))
    (cl-loop
     for lemma in lemmata
     for (lemma-word lemma-nr translation entries) = lemma
     concat (concat (propertize (string-trim
				 (format "%s (%s)"
					 (classicist--perseus-ensure-utf8 lemma-word
									lang)
					 translation))
				'font-lock-face 'link
				'heading 'h3
				'lemma-nr lemma-nr
				'action 'lookup
				'lemma lemma-word
				'lang lang
				'keymap classicist-perseus-action-map
				'rear-nonsticky t)
		    " "
		    (propertize "[Attested Forms]"
				'font-lock-face 'warning
				'action 'forms
				'lemma lemma-word
				'lang lang
				'keymap classicist-perseus-action-map
				'rear-nonsticky t)
		    "\n\n"
		    (cl-loop for (headword . analysis) in entries
			     concat (propertize
				     (format "%-20s → %s\n"
					     (classicist--perseus-ensure-utf8 headword
									    lang)
					     analysis)
				     'h3 t))
		    "\n"))))

(defun classicist--parse-and-show (query lang &optional filter ignore-case no-diacritics)
  "Display all possible morphological analyses for query, with FILTER applied.
 Dispatcher function. IGNORE-CASE and NO-DIACRITICS should be either t or 'ignore;
if nil, query interactively for their values"
  (seq-let (filter ignore-case no-diacritics)
      (classicist--parse-and-show-choose-filter filter ignore-case no-diacritics)
    (let ((results (classicist--parse-all query lang filter ignore-case no-diacritics)))
      (unless results (error "No results for %s!" query))
      (classicist--add-parse-entry)
      (insert (propertize (format "Results for %s:\n" query)
			  'font-lock-face 'shr-h1
			  'heading 'h1))
      (insert (propertize (format "(%s, %s, %s)\n\n"
				  (if (eq filter #'string-equal)
				      "No filter"
				    (format "filtered by %s" filter))
				  (if ignore-case "ignoring case"
				    "case sensitive")
				  (if no-diacritics "ignoring diacritics"
				    "diacritics sensitive"))
			  'font-lock-face 'italic
			  'h1 t))
      (cl-loop for (headword . analyses) in results
	       do (insert
		   (propertize (format "Form %s:\n\n"
				       (if (string= lang "greek")
					   (diogenes--perseus-beta-to-utf8 headword)
					 headword))
			       'font-lock-face 'success
			       'h1 t
			       'heading 'h2))
	       do (insert
		   (propertize (classicist--format-parse-results headword lang analyses)
			       'h1 t
			       'h2 t))))))


;;; Show all attested forms of lemma
(defun classicist--format-lemma-and-forms (lemma lang)
  "Format a LEMMA entry as returned by `classicist--get-all-forms'."
  (concat (propertize (car lemma)
		      'font-lock-face 'shr-h2
		      'heading 'h2
		      'action 'lookup
		      'lemma (cadr lemma)
		      'lang lang
		      'lemma-nr (caddr lemma)
		      'keymap classicist-perseus-action-map
		      'rear-nonsticky t)
	  " \n"
	  (cl-loop
	   for (form . analyses) in (cdddr lemma)
	   concat (propertize
		   (concat (format "%-20s " form)
			   (propertize (car analyses)
				       'font-lock-face 'italic)
			   "\n"
			   (cl-loop
			    for a in (cdr analyses)
			    concat (concat (make-string 21 ? )
					   (propertize a
						       'font-lock-face 'italic)
					   "\n")))
		   'h2 t))
	  "\n"))

(defun classicist--show-all-forms (lemma lang)
  "Show all attested forms of LEMMA in LANG."
  (let ((results (classicist--get-all-forms lemma lang)))
    (unless results (error "No result for %s in %s" lemma lang))
    (classicist-display-buffer (get-buffer-create "*Diogenes Forms*")
			      :kind 'morphology)
    (classicist-analysis-mode)
    (goto-char (point-max))
    (save-excursion
      (mapc (lambda (x)
	      (insert (classicist--format-lemma-and-forms x lang)))
	    (sort results (lambda (a b)
		     (diogenes--sort-alphabetically-no-diacritics (car a)
								  (car b))))))
    t))

;;; Show all lemmata that match query
(defun classicist--show-all-lemmata (query lang &optional filter ignore-case no-diacritics)
  "Show all lemmata that match QUERY in lang, with FILTER applied.
IGNORE-CASE and NO-DIACRITICS should be either t or 'ignore;
if nil, query interactively for their values"
 (seq-let (filter ignore-case no-diacritics)
      (classicist--parse-and-show-choose-filter filter ignore-case no-diacritics)
   (let ((results (classicist--query-all-lemmata query lang filter ignore-case no-diacritics)))
     (unless results (error "No results for lemma %s!" query))
     (classicist-display-buffer (get-buffer-create "*Diogenes Forms*")
			      :kind 'morphology)
     (classicist-analysis-mode)
     (goto-char (point-max))
     (insert (propertize (format "Results for %s:\n" query)
			 'font-lock-face 'shr-h1
			 'heading 'shr-h1))
     (insert (propertize (format "(%s, %s, %s)\n\n"
				 (if (eq filter #'string-equal)
				     "No filter"
				   (format "filtered by %s" filter))
				 (if ignore-case "ignoring case"
				   "case sensitive")
				 (if no-diacritics "ignoring diacritics"
				   "diacritics sensitive"))
			 'font-lock-face 'italic
			 'h1 t))
     (save-excursion
       (mapc (lambda (x)
	       (insert (classicist--format-lemma-and-forms x lang)))
	     (sort results
		   (lambda (a b)
		     (diogenes--sort-alphabetically-no-diacritics (car a)
								  (car b)))))))))


;;; Callback function

(defun classicist-lookup-open-tll-or-tgl ()
  "Open the print thesaurus appropriate to the current entry's language.
For a Latin entry this opens the TLL (Thesaurus Linguae Latinae); for
a Greek entry, Estienne's TGL (Thesaurus Graecae Linguae).  Bound to
\\`t' in `classicist-lookup-mode', it dispatches on the buffer-local
`classicist--lookup-lang' so the same key serves both languages.  A
prefix argument is passed through to the underlying opener (which then
prompts for a word).  If the language is unknown, it defaults to the
TLL, the historical binding of this key."
  (interactive)
  (let ((lang (and (boundp 'classicist--lookup-lang) classicist--lookup-lang)))
    (pcase lang
      ("greek" (call-interactively #'diogenes-lookup-open-tgl))
      (_       (call-interactively #'diogenes-lookup-open-tll)))))


(provide 'classicist-morphology)

;;; classicist-morphology.el ends here
