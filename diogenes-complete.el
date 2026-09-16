;;; diogenes-complete.el --- completing a lemma as one types -*- lexical-binding: t; -*-

;; Keywords: classics, greek, latin, completion
;; Package-Requires: ((emacs "28.1"))

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


;;; The candidates, read once

(defvar diogenes-complete--cache nil
  "Candidates by language: an alist of (LANG . PAIRS).

PAIRS is (CANDIDATE . BARE) for every lemma in that language\\='s word list.
KEPT because the list is long -- the Greek one runs to six figures -- and
because the bare form of a lemma cannot change: doing this once a session is
nothing, and doing it at every keystroke would make the prompt unusable.")

(defun diogenes-complete-forget ()
  "Forget the candidates read from the word lists.
Wanted after changing the Perseus data, and nowhere else."
  (interactive)
  (setq diogenes-complete--cache nil)
  (message "The lemma candidates are forgotten"))

(defun diogenes-complete--pairs (lang)
  "Every lemma of LANG with its bare form, as (CANDIDATE . BARE)."
  (let ((known (assoc lang diogenes-complete--cache)))
    (unless known
      (unless (fboundp 'diogenes--get-all-lemmata)
        (user-error "The Perseus word lists are not available"))
      (let* ((table (diogenes--get-all-lemmata lang))
             (pairs nil))
        (unless (hash-table-p table)
          (user-error "No %s word list to complete on" lang))
        (maphash
         (lambda (lemma _entry)
           (push (cons lemma (diogenes-complete--bare lemma)) pairs))
         table)
        ;; ALPHABETICAL BY THE BARE FORM.  A hash table's own order is no
        ;; order at all, and sorting by the spelling would scatter words that
        ;; belong together -- `a)/nqrwpos' and `a)nqrw/pinos' sort apart when
        ;; the breathings and accents are counted.
        (setq known (cons lang (sort pairs (lambda (a b)
                                             (string-lessp (cdr a) (cdr b))))))
        (push known diogenes-complete--cache)))
    (cdr known)))


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
         (needle (if marked input (diogenes-complete--bare input)))
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
            (let ((completion-styles '(diogenes-lemma))
                  (answer
                   (minibuffer-with-setup-hook
                       (lambda ()
                         (add-hook 'after-change-functions
                                   #'diogenes-complete--convert nil t))
                     (completing-read prompt table nil nil))))
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

(defvar-local diogenes-complete--converting nil
  "Non-nil while this hook is rewriting the minibuffer, to not recurse.")

(defun diogenes-complete--convert (start end _length)
  "Turn Unicode Greek typed in the minibuffer into beta code.

WHY IN THE MINIBUFFER AND NOT IN THE MATCHER.  The matcher is given one string
and could convert it; but the reader must also SEE what will be searched for,
and a prompt that shows `μύω' while matching `mu/w' is a prompt that lies
about what it is doing.  Converting the text itself makes the two the same
thing.  A reader typing beta code notices nothing."
  (unless diogenes-complete--converting
    (let ((typed (buffer-substring-no-properties start end)))
      (when (and (string-match-p "\\cg" typed)
                 (fboundp 'diogenes--utf8-to-beta))
        (let ((diogenes-complete--converting t)
              (beta (diogenes--utf8-to-beta typed)))
          (unless (equal beta typed)
            (save-excursion
              (delete-region start end)
              (goto-char start)
              (insert beta))))))))

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
  (mapcar #'car (cdddr entry)))

(defun diogenes-complete-merge-lemmata (entries)
  "ENTRIES with the duplicates among them merged.

THE SAME RECORD TWICE IS NOT A HOMOGRAPH.  Two entries with the same full
lemma and the same set of forms say the same thing, whatever their offsets,
and offering both is offering a choice that cannot be made."
  (let ((seen (make-hash-table :test #'equal))
        (kept nil))
    (dolist (entry entries)
      (let ((key (cons (nth 1 entry)
                       (sort (copy-sequence
                              (diogenes-complete--entry-forms entry))
                             #'string-lessp))))
        (unless (gethash key seen)
          (puthash key t seen)
          (push entry kept))))
    (nreverse kept)))

(defun diogenes-complete-choose-lemma (entries &optional prompt)
  "Ask which of ENTRIES was meant, and return it.

Returns the one entry where ENTRIES holds only one, or only one once the
duplicates are merged -- in which case nothing is asked."
  (let ((entries (diogenes-complete-merge-lemmata entries)))
    (if (null (cdr entries))
        (car entries)
      (let* ((labels
              (mapcar
               (lambda (entry)
                 (let* ((shown (or (nth 0 entry) "?"))
                        (raw (or (nth 1 entry) "?"))
                        (forms (length (diogenes-complete--entry-forms entry)))
                        (pad (max 1 (- diogenes-complete-greek-width
                                       (string-width shown)))))
                   (cons (format "%s%s%-14s %d form%s"
                                 shown (make-string pad ?\s) raw forms
                                 (if (= forms 1) "" "s"))
                         entry)))
               entries))
             (chosen (completing-read (or prompt "Which lemma? ")
                                      labels nil t)))
        (cdr (assoc chosen labels))))))

(provide 'diogenes-complete)
;;; diogenes-complete.el ends here
