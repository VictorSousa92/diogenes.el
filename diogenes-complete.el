;;; diogenes-complete.el --- completing a lemma as one types -*- lexical-binding: t; -*-

;; Keywords: classics, greek, latin, completion
;; Package-Requires: ((emacs "28.1"))

;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor.goncalves.sousa@alumni.usp.br>

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

;; HOW A LEMMA IS ASKED FOR, AND WHY IT IS HARD TO ANSWER.  The morphological
;; search -- `l' in the search menu, which is the one search of the corpora
;; that finds a WORD rather than a string -- reads its lemma with
;; `read-from-minibuffer': a plain prompt, no candidates, and the exact lemma
;; or nothing.  So does `diogenes-show-all-forms-greek', and so do the other
;; three word-list commands.
;;
;; That is a hard prompt to answer.  A reader must know, before typing:
;;
;;   * whether the word list spells it `mu/w' or `mu/w1', the trailing digit
;;     distinguishing homographs;
;;   * where the breathing and the accent go -- `e)lpi/s' is not `e(lpi/s'
;;     and not `e)lpis';
;;   * and, in Latin, whether the list carries the macrons: `amo' is stored
;;     `amo_'.
;;
;; Get any of it wrong and the answer is an error, or silence.
;;
;; AND THE LIST IS ALREADY IN MEMORY.  `diogenes--get-all-lemmata' reads
;; `greek-lemmata.txt' or `latin-lemmata.txt' into a hash table and caches it.
;; Everything below is a way of letting a reader see into that table while
;; typing, which is what the prompt should have done all along.
;;
;; THE MATCHING RULE, which is the substance of this file: the diacritics one
;; types are the ones one means.
;;
;;   Input with no marks     -> matched against the lemmata with their marks
;;   `muw', `mu'                taken off, so it reaches mu/w, mu/wn, mu/wy
;;                              alike.  The common case, and the one a reader
;;                              who is unsure of the accent needs.
;;
;;   Input with a mark       -> matched as spelled, so `mu/' reaches mu/w and
;;   `mu/w', `μύω'              not mu/wn.  The marks were typed and are
;;                              meant.
;;
;; Greek may be typed as beta code or as Unicode, either way; the input is
;; converted before anything is compared, so the two are one question.
;;
;; WHY A COMPLETION STYLE AND NOT A TABLE.  A table cannot do this on its own
;; under the completion frameworks people run: orderless, which Doom installs,
;; asks the table for everything and then filters the list itself with regexps
;; built from the raw input -- so a table that wanted to match `mu/w' against
;; `μύω' would never be consulted.  A style attached to a CATEGORY is used
;; instead of orderless for that category alone, and leaves every other prompt
;; in Emacs exactly as it was.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'ucs-normalize)

(declare-function diogenes--get-all-lemmata "diogenes-perseus" (lang))
(declare-function diogenes--beta-to-utf8 "diogenes-utils" (str))
(declare-function diogenes--utf8-to-beta "diogenes-utils" (str))

(defgroup diogenes-complete nil
  "Completing a lemma as one types."
  :group 'diogenes
  :prefix "diogenes-complete-")

(defcustom diogenes-complete-lemmata t
  "Whether the lemma prompts offer the word list to complete on.

Non-nil is the prompt described in this file\\='s commentary: candidates as one
types, beta code or Unicode, the diacritics optional.  Nil restores
`read-from-minibuffer\\=' and `(interactive \"s\")\\=', for a reader who would
rather type the lemma exactly and not wait for the list to be read."
  :type 'boolean
  :group 'diogenes-complete)

(defcustom diogenes-complete-prefix-first t
  "Whether prefixes are offered before the middle of a word.

Non-nil offers the lemmata that BEGIN with what was typed, and those that
merely contain it only where no lemma begins with it: `lo\\=' means `lo/gos\\='
before it means `a)nalogi/a\\='.  Nil offers both at once, alphabetically, which
is a longer list and a fairer one."
  :type 'boolean
  :group 'diogenes-complete)


;;; The bare form of a word

(defun diogenes-complete--bare (string)
  "STRING reduced to its letters, lower case.

WHAT IS COMPARED when no diacritic was typed.  Everything that is not a letter
goes: in beta code the diacritics ARE punctuation -- `mu/w\\=' is mu, acute,
omega -- and the asterisk that marks a capital goes with them, which is right,
a reader who omits accents not meaning to distinguish Zeus from zeus.  In
Unicode the marks are combining characters once decomposed, and a precomposed
letter is decomposed here to bring them out.  In Latin the macrons of the word
list, `amo_\\=' and `su^s\\=', go the same way and for the same reason.

Final sigma is made plain, the two being one letter in every question anybody
asks of a word list."
  (let ((letters
         (seq-filter
          (lambda (character)
            (memq (get-char-code-property character 'general-category)
                  '(Ll Lu Lt Lo Lm)))
          (string-to-list (ucs-normalize-NFD-string (downcase string))))))
    (replace-regexp-in-string "ς" "σ" (apply #'string letters))))

(defun diogenes-complete--marked-p (string)
  "Whether STRING carries any diacritic at all.

This is what decides how strictly it is matched, and it is deliberately the
reader\\='s own doing rather than a setting: typing an accent asks for that
accent, and omitting it asks for the word however it is accented."
  (or (string-match-p "[()/\\\\=|+*_^]" string)
      (seq-some (lambda (character)
                  (memq (get-char-code-property character 'general-category)
                        '(Mn Mc Me)))
                (string-to-list (ucs-normalize-NFD-string string)))))

(defun diogenes-complete--as-stored (string lang)
  "STRING as the word list of LANG spells it.

Greek typed as Unicode becomes beta code, the lists being beta code
throughout; Latin is left alone.  `diogenes--greek-ensure-beta\\=' does the same
thing and is not used here, this file being loadable before it."
  (if (and (string= lang "greek")
           (string-match-p "\\cg" string)
           (fboundp 'diogenes--utf8-to-beta))
      (diogenes--utf8-to-beta string)
    string))


;;; The candidates, indexed once and kept on disk

;; WHY A CACHE AT ALL.  `diogenes--get-all-lemmata' parses the whole of
;; `greek-lemmata.txt' into a hash table -- every lemma with every attested
;; form and every analysis of it -- and says so while it works, because it
;; takes a while.  For the prompt that is a great deal of work to do before a
;; reader can type the first letter: what the prompt needs is the LEMMATA, and
;; the forms only matter once one has been chosen.
;;
;; SO THIS INDEXES THE FILE ONCE AND WRITES DOWN THREE THINGS PER LEMMA: how
;; the word list spells it, how that reads as Greek, and how it reads with the
;; diacritics off -- the first for the search, the second for the reader, the
;; third for the matching.  Some hundred thousand lines, written as plain text,
;; one lemma to a line, read back with one `insert-file-contents' and a split.
;;
;; AND THE OFFSETS, which is what makes the forms cheap too.  Each lemma's
;; records are somewhere in the file, and the index remembers where -- so the
;; forms of one lemma are got by reading those few hundred bytes rather than
;; the whole file.  It is the same trick Diogenes uses for its dictionaries,
;; which seek to a byte offset and read a line rather than search.
;;
;; THE CACHE IS CHECKED AGAINST THE FILE, by size and modification time, so a
;; new Perseus release is noticed rather than answered from the old index.
;; `diogenes-complete-rebuild' forces it, for a file changed in place within
;; the same second.

(defcustom diogenes-complete-cache-directory
  (expand-file-name "diogenes-complete/" user-emacs-directory)
  "Where the lemma index is kept.

One file per language, plain text, some megabytes.  Written the first time a
lemma prompt is used and read at every one after."
  :type 'directory
  :group 'diogenes-complete)

(defvar diogenes-complete--cache nil
  "Per language, in memory: an alist of (LANG PAIRS OFFSETS).
PAIRS is (CANDIDATE . BARE) and OFFSETS a hash from a candidate to the places
in the word list where its records are.")

(defun diogenes-complete--lemmata-file (lang)
  "The word list of LANG."
  (unless (fboundp 'diogenes--perseus-path)
    (user-error "Diogenes is not loaded"))
  (let ((file (file-name-concat (diogenes--perseus-path)
                                (concat lang "-lemmata.txt"))))
    (unless (file-readable-p file)
      (user-error "No %s word list at %s" lang file))
    file))

(defun diogenes-complete--cache-file (lang)
  "Where LANG's index is written."
  (expand-file-name (concat lang "-lemmata-index.txt")
                    diogenes-complete-cache-directory))

(defun diogenes-complete--stamp (file)
  "FILE's size and modification time, as one string.
ENOUGH TO NOTICE A NEW RELEASE and cheap to compute; not enough to notice a
file rewritten in place within the same second, which is what
`diogenes-complete-rebuild' is for."
  (let ((attributes (file-attributes file)))
    (format "%d %s"
            (file-attribute-size attributes)
            (format-time-string "%s" (file-attribute-modification-time
                                      attributes)))))

(defun diogenes-complete--build (lang)
  "Read LANG's word list and write the index.  Return (PAIRS OFFSETS).

READ LITERALLY AND BY BYTE.  The offsets written down are byte positions into
the file, which is how they are read back -- `insert-file-contents' takes them
that way -- so the buffer must not be decoded on the way in."
  (let ((file (diogenes-complete--lemmata-file lang))
        (offsets (make-hash-table :test #'equal))
        (greek (string= lang "greek"))
        (pairs nil)
        (lines 0))
    (message "Indexing the %s lemmata, once ..." lang)
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert-file-contents-literally file)
      (goto-char (point-min))
      (while (not (eobp))
        (let* ((start (point))
               (end (line-end-position))
               (tab (save-excursion
                      (goto-char start)
                      (and (search-forward "\t" end t) (1- (point))))))
          (when tab
            (let* ((full (buffer-substring-no-properties start tab))
                   ;; THE KEY IS THE LEMMA WITHOUT ITS HOMOGRAPH DIGIT, as
                   ;; `diogenes--lemmata-file-to-hashtable' has it: `le/gw1'
                   ;; and `le/gw2' are one key and two records, and the
                   ;; records are told apart after the choice, not before it.
                   (key (if (string-match "[0-9]$" full)
                            (substring full 0 (match-beginning 0))
                          full)))
              (puthash key (cons (cons start end) (gethash key offsets))
                       offsets)))
          (setq lines (1+ lines))
          (forward-line 1))))
    ;; The candidates are the keys, converted once.
    ;; THE BARE FORM IS THE BETA LEMMA'S, and this is the one thing here that
    ;; has to be right.  It was the GREEK lemma's bared -- Greek letters with
    ;; the accents off, `μυω' -- while a reader typing `muw' reduces to Latin
    ;; letters, so the two could never be equal and unaccented beta code
    ;; matched nothing at all.  Both sides are now the word list's own script,
    ;; and Unicode input is brought to it before it is compared.  The Greek is
    ;; for the reader to see and for nothing else.
    (maphash
     (lambda (key _places)
       (push (cons key (diogenes-complete--bare key)) pairs))
     offsets)
    (setq pairs (sort pairs (lambda (a b) (string-lessp (cdr a) (cdr b)))))
    (message "Indexing the %s lemmata: %d lines, %d lemmata"
             lang lines (length pairs))
    (diogenes-complete--write lang pairs offsets)
    (list pairs offsets)))

(defun diogenes-complete--write (lang pairs offsets)
  "Write LANG's index: PAIRS and OFFSETS, as plain text."
  (condition-case error
      (progn
        (make-directory diogenes-complete-cache-directory t)
        (with-temp-file (diogenes-complete--cache-file lang)
          ;; VERSION 2: the second column changed meaning, an index written
          ;; by the earlier code holding Greek where this expects beta code.
          (insert (format "# diogenes-complete 2 %s %s\n" lang
                          (diogenes-complete--stamp
                           (diogenes-complete--lemmata-file lang))))
          (dolist (pair pairs)
            (insert (car pair) "\t" (cdr pair) "\t"
                    (mapconcat (lambda (place)
                                 (format "%d-%d" (car place) (cdr place)))
                               (gethash (car pair) offsets) ",")
                    "\n"))))
    ;; A READ-ONLY HOME DIRECTORY is a reason to do the work every session,
    ;; not a reason to fail: the index is a convenience and the prompt works
    ;; without it.
    (error (message "Could not write the lemma index: %s"
                    (error-message-string error)))))

(defun diogenes-complete--read (lang)
  "LANG's index from its cache file, or nil where there is none to trust."
  (let ((file (diogenes-complete--cache-file lang)))
    (when (file-readable-p file)
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (let ((header (buffer-substring-no-properties
                           (point) (line-end-position)))
                  (wanted (format "# diogenes-complete 2 %s %s" lang
                                  (diogenes-complete--stamp
                                   (diogenes-complete--lemmata-file lang)))))
              ;; STALE IS WORSE THAN ABSENT: a word list replaced by a new
              ;; release would otherwise go on being answered from the old
              ;; index, and a lemma that is simply missing is the hardest
              ;; kind of fault to think to blame on a cache.
              (when (equal header wanted)
                (forward-line 1)
                (let ((offsets (make-hash-table :test #'equal))
                      (pairs nil))
                  (while (not (eobp))
                    (let ((fields (split-string
                                   (buffer-substring-no-properties
                                    (point) (line-end-position))
                                   "\t")))
                      (when (= (length fields) 3)
                        (push (cons (nth 0 fields) (nth 1 fields)) pairs)
                        (puthash (nth 0 fields)
                                 (mapcar
                                  (lambda (place)
                                    (let ((two (split-string place "-")))
                                      (cons (string-to-number (nth 0 two))
                                            (string-to-number (nth 1 two)))))
                                  (split-string (nth 2 fields) "," t))
                                 offsets)))
                    (forward-line 1))
                  (list (nreverse pairs) offsets)))))
        (error nil)))))

(defun diogenes-complete--index (lang)
  "LANG's index, from memory, from the cache file, or built."
  (let ((known (assoc lang diogenes-complete--cache)))
    (unless known
      (setq known (cons lang (or (diogenes-complete--read lang)
                                 (diogenes-complete--build lang))))
      (push known diogenes-complete--cache))
    (cdr known)))

(defun diogenes-complete--pairs (lang)
  "Every lemma of LANG with its bare form, as (CANDIDATE . BARE)."
  (nth 0 (diogenes-complete--index lang)))

(defun diogenes-complete-records (lemma lang)
  "The word list's records for LEMMA in LANG, read by offset.

THE FEW HUNDRED BYTES THAT MATTER.  A lemma's records are at known places in
the file, so they are read from those places -- which is the whole point of
keeping the offsets, and means that choosing a lemma costs no more than
looking one up.

Each record comes back in the shape `diogenes--process-lemma' expects:
\\(FULL-LEMMA NUMBER . ENTRIES)."
  (let* ((index (diogenes-complete--index lang))
         (places (gethash lemma (nth 1 index)))
         (file (diogenes-complete--lemmata-file lang))
         (records nil))
    (dolist (place places)
      (let ((line (with-temp-buffer
                    (set-buffer-multibyte nil)
                    (insert-file-contents-literally
                     file nil (1- (car place)) (1- (cdr place)))
                    (decode-coding-string (buffer-string) 'utf-8))))
        (let ((fields (split-string line "\t")))
          (when (cdr fields)
            (push (nconc (list (nth 0 fields)
                               (string-to-number (nth 1 fields)))
                         (cddr fields))
                  records)))))
    (nreverse records)))

(defun diogenes-complete-forget ()
  "Forget the lemma index held in memory.
The files on disk are kept: they carry the word list's own size and time and
are passed over of their own accord once that has changed."
  (interactive)
  (setq diogenes-complete--cache nil)
  (message "The lemma index is forgotten"))

;;;###autoload
(defun diogenes-complete-rebuild (&optional lang)
  "Index the word list again, LANG or both, and write it.

Wanted where a word list has been changed in place within the same second as
before -- which the size and time cannot see -- and after a Perseus release
that happens to be the same length, which would be a remarkable coincidence
and is cheap to rule out."
  (interactive (list (completing-read "Language: " '("greek" "latin") nil t)))
  (dolist (one (if lang (list lang) '("greek" "latin")))
    (setq diogenes-complete--cache
          (assoc-delete-all one diogenes-complete--cache))
    (ignore-errors
      (push (cons one (diogenes-complete--build one))
            diogenes-complete--cache))))

;;; The style

(defvar diogenes-complete--pairs nil
  "The candidates the style is to filter.
Bound around a prompt rather than set, so that a Greek prompt and a Latin one
do not have to know about each other.")

(defun diogenes-complete--filter (input pairs)
  "The candidates in PAIRS that INPUT points at.

See this file\\='s commentary for the rule.  The language is not needed here:
the input has already been brought to the spelling of the list it is being
matched against."
  (let* ((marked (diogenes-complete--marked-p input))
         ;; CONVERTED HERE AND NOWHERE ELSE.  Greek typed at the prompt is
         ;; brought to the word list's spelling before anything is compared --
         ;; one short string, once per keystroke -- so `μύω' and `mu/w' are
         ;; one question and the text the reader typed is left as they typed
         ;; it.  Converting the minibuffer itself was the first attempt and
         ;; was wrong twice over: it rewrote what a reader was in the middle
         ;; of typing, and with an input method it converted a combining mark
         ;; on its own and made nonsense of the rest.
         (stored (if (and (string-match-p "\\cg" input)
                          (fboundp 'diogenes--utf8-to-beta))
                     (diogenes--utf8-to-beta input)
                   input))
         (needle (if marked stored (diogenes-complete--bare stored)))
         (get (if marked #'car #'cdr)))
    (cond
     ((string-empty-p needle) (mapcar #'car pairs))
     (t
      (let ((prefixes nil)
            (inside nil))
        (dolist (pair pairs)
          (let ((against (funcall get pair)))
            (cond ((string-prefix-p needle against)
                   (push (car pair) prefixes))
                  ((string-search needle against)
                   (push (car pair) inside)))))
        (setq prefixes (nreverse prefixes))
        (setq inside (nreverse inside))
        (if diogenes-complete-prefix-first
            (or prefixes inside)
          (append prefixes inside)))))))

(defun diogenes-complete--all (string _table pred _point)
  "Every completion of STRING, by our own rule."
  (let ((pairs (or diogenes-complete--pairs nil)))
    (when pred
      (setq pairs (seq-filter (lambda (pair) (funcall pred (car pair)))
                              pairs)))
    (diogenes-complete--filter string pairs)))

(defun diogenes-complete--try (string table pred point)
  "Complete STRING as far as it goes, which is usually not at all.
One match is taken; anything else is left as typed, `TAB' having nothing
useful to do with forty Greek words beyond showing them."
  (let ((matches (diogenes-complete--all string table pred point)))
    (cond
     ((null matches) nil)
     ((and (null (cdr matches)) (not (equal (car matches) string)))
      (cons (car matches) (length (car matches))))
     (t (cons string point)))))

(add-to-list 'completion-styles-alist
             '(diogenes-lemma
               diogenes-complete--try
               diogenes-complete--all
               "Lemmata by beta code or Unicode, diacritics optional."))

(add-to-list 'completion-category-overrides
             '(diogenes-lemma (styles diogenes-lemma)))


;;; The prompt

;;;###autoload
(defun diogenes-read-lemma (lang &optional prompt)
  "Read a lemma of LANG, completing on its word list, and return it as stored.

LANG is \"greek\" or \"latin\".  What comes back is spelled as the word list
spells it -- beta code for Greek -- which is what every caller wants, none of
them having any use for the Unicode a reader may have typed.

Falls back on a plain prompt where `diogenes-complete-lemmata\\=' is nil or the
word list cannot be read, so a caller may use this unconditionally."
  (let ((prompt (or prompt (format "Lemma (%s): " lang))))
    (if (not diogenes-complete-lemmata)
        (diogenes-complete--as-stored (read-from-minibuffer prompt) lang)
      (let* ((pairs (ignore-errors (diogenes-complete--pairs lang))))
        (if (not pairs)
            (diogenes-complete--as-stored (read-from-minibuffer prompt) lang)
          (let* ((diogenes-complete--pairs pairs)
                 (candidates (mapcar #'car pairs))
                 (shown
                  ;; GREEK IS SHOWN AS GREEK, AND FIRST.  The list is beta
                  ;; code and a reader completing on `memuk' is completing on
                  ;; nothing they can read -- so the Greek goes in front,
                  ;; where the eye is, and the beta follows it, that being
                  ;; what one may want to copy and what the search will
                  ;; actually use.
                  ;;
                  ;; IT HAS TO BE THE PREFIX and cannot be the candidate: the
                  ;; candidate IS the string that comes back and that the
                  ;; style matches against, and both of those must be the beta
                  ;; the word list is keyed on.  An affixation is displayed
                  ;; PREFIX CANDIDATE SUFFIX, so putting the Greek in the
                  ;; prefix puts it first without changing what anything else
                  ;; sees.
                  (and (string= lang "greek")
                       (fboundp 'diogenes--beta-to-utf8)))
                 (table
                  (lambda (string predicate action)
                    (pcase action
                      ('metadata
                       `(metadata
                         (category . diogenes-lemma)
                         (display-sort-function . identity)
                         (cycle-sort-function . identity)
                         ,@(when shown
                             `((affixation-function
                                . ,#'diogenes-complete--affix)))))
                      (_ (complete-with-action action candidates
                                               string predicate))))))
            ;; THE INPUT IS BROUGHT TO THE LIST'S OWN SPELLING BEFORE IT IS
            ;; MATCHED, which is why Unicode works: what the style compares is
            ;; beta against beta, and the conversion happens here, once per
            ;; keystroke, on one short string.
            (let ((answer (completing-read prompt table nil nil)))
              ;; WHAT COMES BACK is either a candidate -- already the word
              ;; list's own spelling -- or whatever was typed, which is
              ;; converted here, once, at the end.
              (diogenes-complete--as-stored (string-trim answer) lang))))))))

(defcustom diogenes-complete-greek-width 20
  "How wide the Greek column is, in display columns.

The Greek is shown before the beta code and padded to this, so that the beta
lines up down the page: a column of it that wandered with the length of each
Greek word would be harder to read than no column at all.  Twenty, because
`a)/nqrwpos\=' converted is nine and the compounds run to twenty."
  :type 'integer
  :group 'diogenes-complete)

(defun diogenes-complete--affix (candidates)
  "CANDIDATES as (BETA GREEK-PREFIX EMPTY-SUFFIX), for the completion display."
  (mapcar
   (lambda (candidate)
     (let* ((greek (diogenes--beta-to-utf8 candidate))
            (pad (max 1 (- diogenes-complete-greek-width
                           (string-width greek)))))
       (list candidate
             (concat greek (make-string pad ?\s))
             "")))
   candidates))

;;;###autoload
(defun diogenes-read-greek-lemma (&optional prompt)
  "Read a Greek lemma with completion; return beta code."
  (diogenes-read-lemma "greek" (or prompt "Greek lemma: ")))

;;;###autoload
(defun diogenes-read-latin-lemma (&optional prompt)
  "Read a Latin lemma with completion."
  (diogenes-read-lemma "latin" (or prompt "Latin lemma: ")))

;;; Choosing between the records of one lemma

;; WHY THERE IS A SECOND PROMPT AT ALL.  The word list is keyed on the lemma
;; with its homograph digit taken OFF -- `diogenes--lemmata-file-to-hashtable'
;; strips a trailing number -- so one key collects every record spelled that
;; way: `le/gw1' and `le/gw2' are LSJ's two verbs, to gather and to say, and
;; they arrive together under `le/gw'.  `diogenes--lemma-forms-list' then asks
;; which was meant, and asked it with `completing-read' over the processed
;; entries, whose car is the lemma as converted -- which for three records of
;; one spelling is three identical lines.  A choice between indistinguishables
;; is not a choice.
;;
;; SO TWO THINGS HAPPEN HERE.  Records that are the same record -- same full
;; lemma and the same forms, which the list does hold in places -- are merged,
;; and where that leaves one there is nothing to ask.  What remains is labelled
;; with what distinguishes it: the full lemma with its digit, the dictionary
;; offset, and how many forms are attested, which is usually the thing that
;; tells a reader which of two homographs is the one they meant.

(defun diogenes-complete--entry-forms (entry)
  "The forms of ENTRY, as processed by `diogenes--process-lemma'.
ENTRY is (LEMMA RAW-LEMMA NUMBER . FORMS), each form being (FORM . ANALYSES)."
  (cdddr entry))

(defun diogenes-complete-merge-lemmata (entries)
  "ENTRIES grouped by the dictionary entry each points at.

THE NUMBER IS THE ANSWER.  Every record of the word list carries one -- the
third element of a processed entry, and the byte offset of the article in the
dictionary, which is how Diogenes reaches an article at all: it seeks to the
offset and reads.  So two records with the SAME number are two records of ONE
article, whatever else differs between them, and offering a reader a choice
between them is offering a choice that has no answer.  Their forms are
UNIONED, which is what the records were: the word list splits a long entry's
forms across more than one line.

Two records with DIFFERENT numbers are two articles -- LSJ's λέγω to gather
and λέγω to say, stored `le/gw1' and `le/gw2' under the one key, the word
list being keyed on the lemma with its homograph digit taken off.  That choice
is real and is put to the reader.

Grouped by the number AND the full lemma, the pair being what identifies an
article; the first record's spelling and order are kept."
  (let ((groups nil))
    (dolist (entry entries)
      (let* ((key (list (nth 1 entry) (nth 2 entry)))
             (known (assoc key groups)))
        (if known
            ;; UNIONED BY THE FORM, keeping the analyses first seen: the same
            ;; form in two records of one article is the same form.
            (setcdr known
                    (let ((merged (cdr known)))
                      (dolist (form (diogenes-complete--entry-forms entry))
                        (unless (assoc (car form) (cdddr merged))
                          (setcdr (last merged) (list form))))
                      merged))
          (push (cons key (copy-sequence entry)) groups))))
    (mapcar #'cdr (nreverse groups))))

(defun diogenes-complete--lemma-labels (entries)
  "ENTRIES as an alist of (LABEL . ENTRY), each label distinguishing its own.

THE NUMBER IS SHOWN ONLY WHERE IT HAS TO BE.  Where the full lemmas differ --
`le/gw1' against `le/gw2' -- that is what a reader recognises and the offset
is noise.  Where they do not, the offset is the only thing that tells the two
apart and leaving it out would reproduce the fault this replaced."
  (let* ((raws (mapcar (lambda (entry) (nth 1 entry)) entries))
         (ambiguous (/= (length (delete-dups (copy-sequence raws)))
                        (length raws))))
    (mapcar
     (lambda (entry)
       (let* ((shown (or (nth 0 entry) "?"))
              (raw (or (nth 1 entry) "?"))
              (number (nth 2 entry))
              (forms (length (diogenes-complete--entry-forms entry)))
              (pad (max 1 (- diogenes-complete-greek-width
                             (string-width shown)))))
         (cons (format "%s%s%-14s %s%d form%s"
                       shown (make-string pad ?\s) raw
                       (if (and ambiguous number)
                           (format "entry %s, " number) "")
                       forms (if (= forms 1) "" "s"))
               entry)))
     entries)))

(defun diogenes-complete-choose-lemma (entries &optional prompt)
  "Ask which of ENTRIES was meant, and return it.

Nothing is asked where the records turn out to be one article: see
`diogenes-complete-merge-lemmata', which is where the question of what counts
as one lemma is actually settled."
  (let ((entries (diogenes-complete-merge-lemmata entries)))
    (if (null (cdr entries))
        (car entries)
      (let ((labels (diogenes-complete--lemma-labels entries)))
        (cdr (assoc (completing-read (or prompt "Which lemma? ")
                                     labels nil t)
                    labels))))))

(provide 'diogenes-complete)
;;; diogenes-complete.el ends here
