;;; diogenes-browser.el --- Corpus browser for diogenes.el -*- lexical-binding: t -*-

;; Copyright (C) 2024 Michael Neidhart
;;
;; Author: Michael Neidhart <mayhoth@gmail.com>
;; Keywords: classics, tools, philology, humanities

;;; Commentary:

;; This file contains functions for browsing the Corpora that Diogenes can read

;;; Code:
(require 'cl-lib)
(require 'text-property-search)  ; prop-match-value, text-property-search-backward
(require 'seq)
(require 'diogenes-lisp-utils)
(require 'diogenes-dict-faces)          ; diogenes-browser-header
(require 'diogenes-perl-interface)

;; Called across files that cannot be required from here without a
;; cycle, and -- where the name is one of this package's own caches --
;; defined inside a `let', which the compiler does not count as a
;; definition at all.
(declare-function diogenes--select-author-num "diogenes-user-interface" (options &optional regex))
(declare-function diogenes--select-work-num "diogenes-user-interface" (options author))
(declare-function diogenes--select-passage "diogenes-user-interface" (options author work))
(declare-function diogenes-lookup-in-dictionary "diogenes-perseus" (&optional word parse))

;;;; --------------------------------------------------------------------
;;;; BROWSER
;;;; --------------------------------------------------------------------

;;; Simple commands
(defun diogenes--send-cmd-to-browser (cmd)
  (let ((diogenes-process (or (get-buffer-process (current-buffer))
			      (error (format "No process in buffer %s!"
					     (current-buffer))))))
    (process-send-string diogenes-process (concat cmd "\n"))))

(defun diogenes--browser-set-height (height)
  (interactive "NLines to display: ")
  (diogenes--send-cmd-to-browser (number-to-string height)))

(defun diogenes-browser-forward ()
  "Load the next page from the Diogenes browser.
Takes no prefix argument: how much to advance is the window's own height
less `next-screen-context-lines', not something to count."
  (interactive)
  (setq diogenes--browser-backwards nil)
  (goto-char (point-max))
  (diogenes--send-cmd-to-browser
   (concat (number-to-string (- (floor (window-screen-lines))
				next-screen-context-lines))
	   "n")))

(defun diogenes-browser-backward ()
  "Load the previous page from the Diogenes browser.
Takes no prefix argument, as `diogenes-browser-forward' takes none."
  (interactive)
  (setq diogenes--browser-backwards t)
  (goto-char (point-min))
  (diogenes--send-cmd-to-browser
   (concat (number-to-string (- (floor (window-screen-lines))
				next-screen-context-lines))
	   "p")))

(defun diogenes-browser-quit ()
  (interactive)
  (diogenes--send-cmd-to-browser "q"))

(defun diogenes-browser-forward-line (&optional N)
  (interactive "p")
  (forward-line N)
  (when (eobp) (diogenes-browser-forward)))

(defun diogenes-browser-backward-line (&optional N)
  (interactive "p")
  (forward-line (- N))
  (when (bobp) (diogenes-browser-backward)))

(defun diogenes-browser-beginning-of-buffer (&optional N)
  (interactive "^P")
  (when (and (not N) (bobp))
    (diogenes-browser-backward))
  (beginning-of-buffer N))

(defun diogenes-browser-end-of-buffer (&optional N)
  (interactive "^P")
  (when (and (not N) (eobp))
    (diogenes-browser-forward))
  (end-of-buffer N))



;;; Utility commands
(defun diogenes-browser-toggle-citations ()
  "Toggle display of the embedded citations in the Diogenes Browser."
  (interactive)
  (save-excursion
    (cond (diogenes-browser-show-citations
	   (setq diogenes-browser-show-citations nil)
	   (goto-char (point-min))
	   (let (cit-match)
	     (while (setq cit-match
			  (text-property-search-forward 'diogenes-citation))
	       (delete-region (prop-match-beginning cit-match)
			      (prop-match-end cit-match)))))
	  (t
	   (setq diogenes-browser-show-citations t)
	   (goto-char (point-min))
	   (let (prop-change)
	     (while (and (setq prop-change
			       (next-single-property-change (point) 'cit))
			 (goto-char prop-change)
			 (not (eobp)))
	       (when-let* ((citation (get-text-property (point) 'cit)))
		 (insert (diogenes--browser-format-citation citation)))))))))

(defcustom diogenes-browser-join-broken-words t
  "Whether a word broken across two lines is joined before it is looked up.
A text may divide a word at the end of a line, and `C-c C-c\=' on either half
looked up that half -- `praeci\=' and `pitur\=' rather than `praecipitur\=', neither
of which any dictionary has.

Only where the buffer SAYS the word is divided: a hyphen at the end of the line,
or the record `C-c C--\=' leaves behind when it removes one.  A line merely
ending in the middle of a phrase is not evidence, and guessing there would join
two ordinary words as often as it mended a broken one.

The halves are joined for the lookup only; the buffer is not touched.
`C-c C--\=' (`diogenes-browser-remove-hyphenation\=') is still there for joining
them in the text itself."
  :type 'boolean
  :group 'diogenes)

(defun diogenes-browser--word-at-point-joined ()
  "The word at point, joined with its other half where the text divided it.
Returns nil where there is nothing to join, so a caller falls back on the
ordinary word at point.

TWO KINDS OF EVIDENCE, and nothing else counts.

A HYPHEN at the end of the line, which is the text saying so outright.

Or the record `diogenes-browser-remove-hyphenation\=' leaves when it removes one:
it puts `hyphen-start\=' on the line that held the first half and `hyphen-end\=' on
the line that held the second, with the halves as their values.  So a buffer
whose hyphens have been removed still knows where they were, and a word already
joined in the text needs nothing done to it -- the property is how we can tell
that case from a word that was never divided at all.

A line that merely ends in the middle of a phrase is NOT evidence.  An earlier
draft guessed there, on the grounds that the next line began lower-case, and
would have joined two perfectly good words in verse as often as it mended a
broken one.  Where a text divides a word and prints no hyphen, this returns nil
and the reader gets the half -- which is what they got before, and honest."
  (save-excursion
    (let ((bounds (bounds-of-thing-at-point 'word)))
      (when bounds
        (let* ((start (car bounds))
               (end (cdr bounds))
               (word (buffer-substring-no-properties start end)))
          (goto-char end)
          ;; The word may or may not include the hyphen, depending on the
          ;; buffer's syntax table -- `thing-at-point' asks that table, and a
          ;; hyphen is a word constituent in some modes and not others.  So the
          ;; word is trimmed of a trailing hyphen and point put before it, and
          ;; the tests below need not care which happened.
          (when (string-suffix-p "-" word)
            (setq word (substring word 0 -1))
            (goto-char (1- end)))
          (cond
           ;; A hyphen at the end of the line.
           ((looking-at-p "-[ \t]*$")
            (diogenes-browser--second-half word))
           ;; Or a line whose hyphen was REMOVED, with point on the first half:
           ;; `diogenes-browser-remove-hyphenation' recorded that half as the
           ;; value of `hyphen-start', so the two agreeing is the evidence.
           ;;
           ;; Agreeing MATTERS.  That property is put on the whole line, so it
           ;; is there whether the word is still divided or has been joined --
           ;; and an earlier draft, taking its mere presence for `already
           ;; joined, do nothing', answered nil for a word that was still in
           ;; halves.  A word already joined reads `praecipitur' where the
           ;; property records `prae', they do not agree, and this falls through
           ;; to nil of itself: no clause is needed for it.
           ((and (equal (get-text-property (line-beginning-position)
                                           'hyphen-start)
                        word)
                 (looking-at-p "[ \t]*$"))
            (diogenes-browser--second-half word))
           (t nil)))))))

(defun diogenes-browser--second-half (first-half)
  "FIRST-HALF joined to the first word of the next line, or nil.
The citation is skipped: it is a text property, `cit\=', so whatever the reader
has chosen to show or hide, the line numbers are never taken for part of the
word."
  (save-excursion
    (forward-line 1)
    (while (and (not (eobp)) (get-text-property (point) 'cit))
      (goto-char (or (next-single-property-change (point) 'cit)
                     (line-end-position))))
    (skip-chars-forward " \t")
    (when-let* ((tail (bounds-of-thing-at-point 'word)))
      (concat first-half
              (buffer-substring-no-properties (car tail) (cdr tail))))))

(defun diogenes-browser-remove-hyphenation (&optional mark-with-vertical-bar)
  "Join all hyphenated words in the current Diogenes Browser Buffer."
  (interactive "P")
  (unless (eq major-mode 'diogenes-browser-mode)
    (error "Not in a Diogenes Browser buffer!"))
  (with-undo-amalgamate
   (save-excursion
     (goto-char (point-min))
     (let (pos-a)
       (while (setq pos-a (and (re-search-forward "\\([^ <-]+\\)-\\s-*$" nil t)
			       (cons (match-beginning 1)
				     (match-end 1))))
	 (when-let* ((line-a (text-property-search-backward 'cit))
		     (line-b (text-property-search-forward 'cit nil nil t))
		     (pos-b  (and (goto-char (prop-match-beginning line-b))
				  (re-search-forward "\\S-+"
						     (point-max) t)
				  (cons (match-beginning 0)
					(match-end 0))))
		     (word-a (buffer-substring-no-properties (car pos-a)
							     (cdr pos-a)))
		     (word-b (buffer-substring-no-properties (car pos-b)
							     (cdr pos-b))))
	   (put-text-property (prop-match-beginning line-a)
			      (prop-match-end line-a)
			      'hyphen-start word-a)
	   (put-text-property (prop-match-beginning line-b)
			      (prop-match-end line-b)
			      'hyphen-end word-b)	
	   (delete-region (car pos-b) (1+ (cdr pos-b)))
	   (goto-char (cdr pos-a))
	   (delete-char 1)
	   (when mark-with-vertical-bar (insert-and-inherit "|"))
	   (insert-and-inherit word-b))
	 (goto-char (cdr pos-a)))))))

(defun diogenes-browser-reinsert-hyphenation ()
  (interactive)
  (unless (eq major-mode 'diogenes-browser-mode)
    (error "Not in a Diogenes Browser buffer!"))
  (with-undo-amalgamate
    (save-excursion
      (goto-char (point-min))
      (let (line-a line-b)
	(while (and (setq line-a (text-property-search-forward 'hyphen-start))
		    (setq line-b (text-property-search-forward 'hyphen-end)))
	  (let ((word-a (prop-match-value line-a))
		(word-b (prop-match-value line-b))
		(bol-a (prop-match-beginning line-a))
		(bol-b (prop-match-beginning line-b))
		(eol-a (prop-match-end line-a))
		(eol-b (prop-match-end line-b)))
	    (remove-text-properties bol-a eol-a '(hyphen-start nil))
	    (remove-text-properties bol-b eol-b '(hyphen-end nil))
	    (let ((prop-a (text-properties-at bol-a))
		  (prop-b (text-properties-at bol-b)))
	      (goto-char bol-b)
	      (insert (apply #'propertize (concat word-b " ")
			     prop-b))
	      (goto-char eol-a)
	      (re-search-backward (regexp-quote word-b))
	      (delete-char (length word-b))
	      (when (string= (buffer-substring (1- (point)) (point))
			     "|")
		(delete-char -1))
	      (insert (apply #'propertize "-"
			     prop-a)))))))))

(defun diogenes-browser-lookup ()
  "Lookup word at point."
  (interactive)
  (funcall (intern (concat "diogenes-parse-and-lookup-"
			   diogenes--browser-language))
	   (replace-regexp-in-string "[^[:alpha:]]" ""
				     (thing-at-point 'word))))

;;; Browser Mode
(defvar diogenes-browser-mode-map
  (let ((map (nconc (make-sparse-keymap) text-mode-map)))
    ;; Overrides of movement keys
    (keymap-set map "<remap> <previous-line>"       #'diogenes-browser-backward-line)
    (keymap-set map "<remap> <next-line>"           #'diogenes-browser-forward-line)
    (keymap-set map "<remap> <beginning-of-buffer>" #'diogenes-browser-beginning-of-buffer)
    (keymap-set map "<remap> <end-of-buffer>"       #'diogenes-browser-end-of-buffer)
    (keymap-set map "q" #'quit-window)
    (keymap-set map "C-c C-n"  #'diogenes-browser-forward)
    (keymap-set map "C-c C-p"  #'diogenes-browser-backward)
    ;; Actions
    (keymap-set map "C-c C-c" #'diogenes-browser-lookup)
    (keymap-set map "C-c C-o" #'diogenes-lookup-in-dictionary)
    (keymap-set map "C-c C-q" #'diogenes-browser-quit)
    ;; Utilities
    (keymap-set map "C-c C--" #'diogenes-browser-remove-hyphenation)
    (keymap-set map "C-c C-+" #'diogenes-browser-reinsert-hyphenation)
    (keymap-set map "C-c C-t" #'diogenes-browser-toggle-citations)
    map)
  "Basic mode map for the Diogenes Browser.")

(define-derived-mode diogenes-browser-mode text-mode "Diogenes Browser"
  "Major mode to browse Diogenes' databases."
  (make-local-variable 'diogenes--browser-backwards)
  (make-local-variable 'diogenes--browser-language)
  (make-local-variable 'diogenes--browser-first-insertion))



;;; Browser process filter
(defun diogenes--browser-format-citation (citation)
  (propertize (format "%-14s"
		      (mapconcat (lambda (x) (format "%s" x))
				 citation
				 "."))
	      'diogenes-citation t
	      'face 'font-lock-comment-face
	      'font-lock-face 'font-lock-comment-face
	      'rear-nonsticky t))

(defun diogenes--browser-format-header (header-lines)
  (propertize (concat (string-join header-lines
				   "\n")
		      "\n\n")
	      'diogenes-header t
	      'face 'diogenes-browser-header
	      'font-lock-face 'diogenes-browser-header
	      ;; 'read-only t
	      'front-sticky t
	      'rear-nonsticky t))

(defvar-local diogenes--browser-output-buffer ""
  "Buffers the output of the diogenes browser output, if it is an
incomplete lisp expression.")
(defun diogenes--read-browser-output (str)
  "Try to read a lisp expression from browser output.
If it is incomplete, buffer it and prepend it when called again."
  (let ((form (ignore-errors (read (concat diogenes--browser-output-buffer
					   str)))))
    (cond ((and form (listp form))
	   (setq diogenes--browser-output-buffer "") form)
	  (t (setq diogenes--browser-output-buffer
		   (concat diogenes--browser-output-buffer str))
	     nil))))

(defun diogenes--browser-filter (proc string)
  (when (buffer-live-p (process-buffer proc))
    (when-let* ((data (diogenes--read-browser-output string)))
     (with-current-buffer (process-buffer proc)
       (seq-let (cit header &rest lines) data
	 (unless lines (error "No input received!"))
	 (cond ((and (boundp 'diogenes--browser-backwards)
		     diogenes--browser-backwards)
		(cond (header (goto-char (point-min))
			      (newline)
			      (goto-char (point-min)))
		      (t (or (text-property-search-forward 'diogenes-header)
			     (goto-char (point-min))))))
	       (t (goto-char (point-max))))
	 (when header (insert (diogenes--browser-format-header header)))
	 (let ((pos (point)))
	   (dolist (alist lines)
	     (when diogenes-browser-show-citations
	       (insert (diogenes--browser-format-citation (car alist))))
	     (insert (propertize (format "%s\n" (cdr alist))
				 'cit (car alist))))
	  (set-marker (process-mark proc) (point-max))
	  (cond (diogenes-browser-first-insertion
		 (setq diogenes-browser-first-insertion nil)
		 (goto-char pos))
		(t (recenter -1 t)))))))))

(defvar-local diogenes--browser-corpus nil
  "The corpus this browser buffer is reading -- `tlg\=', `phi\=', and the rest.
Recorded so that the buffer can say what it is showing.  It could not: a
browser buffer knew its LANGUAGE and nothing else, so nothing outside it could
name the passage on the screen -- not a link to it, not a citation, not a
message.  Set where the buffer is made, that being the one place every route in
passes through.")

(defvar-local diogenes--browser-author nil
  "The author number this browser buffer is reading; see
`diogenes--browser-corpus\='.")

(defvar-local diogenes--browser-work nil
  "The work number this browser buffer is reading; see
`diogenes--browser-corpus\='.")

(defvar-local diogenes--browser-labels nil
  "What the levels of this work's citations are called, outermost first.
`(\"book\" \"verse\")\=', `(\"Bekker page\" \"line\")\=', `(\"Stephanus page\"
\"section\" \"line\")\=' -- Diogenes's own data says, per work, and a citation is a
list in exactly that order.

Recorded once when the buffer is made rather than asked for each time it is
wanted: `diogenes--get-work-labels\=' is a call into Perl, which is cheap once and
not cheap per reference.

This is what makes a citation renderable.  `(1053a 15)\=' is conventionally
written `1053a15\=' and `(4 208)\=' is written `4.208\=', and the difference is not
the author but the LEVEL: a page and a line run together, numbered levels take a
stop between them.  Without the labels there is no way to tell which is which,
and rendering would have to know a convention per author -- an open set, where
the levels are a handful.")

(defvar-local diogenes--browser-passage nil
  "The passage this browser buffer was opened at, if one was given.
Where the reader answered `no\=' to `Specify passage?\=' this is nil and the
buffer began at the start of the work.  It is where it BEGAN, not where it now
is: paging moves the buffer and does not update this, the position being the
Perl process's to know.")

(defcustom diogenes-citation-run-on-labels
  '("page" "pg" "column" "folio")
  "Levels that run into the level after them, with no stop between.
Aristotle is cited `1053a15\=' and Plato `246a4\=', the page and what follows
written as one; a book and a verse are cited `4.208\=', with a stop.  The
difference is the LEVEL and not the author, which is why this is a list of
labels: Diogenes names the levels of every work -- `(\"book\" \"verse\")\=',
`(\"Stephanus page\" \"section\" \"line\")\=' -- so one rule per label covers every
author who uses it.

`pg\=' is there because the corpora abbreviate: the scan finds `pg\=' 341 times
beside `page\=' 1785, and `ln\=', `vol\=', `sect\=' and `chap\=' likewise beside their
full forms.  Only the paginated ones need listing, the rest taking stops anyway.

Matched as SUBSTRINGS of a label, so `page\=' covers `Stephanus page\=',
`Bekker page\=', `Jebb page\=' and the twenty-odd other editors' pages the two
corpora use -- including any this list has never heard of, which a list of whole
labels could not do.

This affects DISPLAY only.  What a link records is
`diogenes-citation-to-key\=', which puts a stop between every level whatever
their labels, because that is reversible and a run-on citation is not: `1053a15\='
cannot be split back into a page and a line without already knowing which is
which.  So a pattern missing from this list costs a reader `1053a.15\=' where they
would write `1053a15\=', and costs nothing that has to work."
  :type '(repeat string)
  :group 'diogenes)

(defun diogenes--citation-runs-on-p (label)
  "Whether LABEL runs into the level after it, with no stop between.
Matched as SUBSTRINGS, case-insensitively, and both parts of that were learnt
from the data rather than guessed.

Substrings, because every editor's page is its own level.  A pass over all 2194
authors of the TLG and the PHI turns up `page\=' itself 1785 times and then
`Stephanus page\=', `Bekker page\=', `Jebb page\=', `Harduin page\=', `Morel page\=',
`Olearius page\=', `Aubert page\=', `Thevenot page\=', `Wescher page\=', `Spengel
page\=', `Dietz page\=', `Usener page\=', `Dindorf page\=', `Kallierges page\=',
`Hermann page\=', `Klein page\=', `Walz page\=', `MPG page\=', `codex page\=',
`Dindorf-Stephanus page\=', `page+column\=', `Bekker page+line\=' -- and there will
be editors neither of us has met.  A LIST of labels would have to name each; the
pattern `page\=' catches them all.

Case-insensitively, because the corpora do not agree: the TLG capitalises --
`Book\=', `Line\=', `Fragment\=', `Ode\=' -- and the PHI does not.  And trimmed,
because at least one work carries a label with a leading space."
  (when label
    (let ((clean (string-trim (downcase label))))
      (and (cl-some (lambda (pattern)
                      (string-match-p (regexp-quote (downcase pattern)) clean))
                    diogenes-citation-run-on-labels)
           t))))

(defun diogenes-citation-to-string (citation &optional labels)
  "CITATION written as a reader would write it.
LABELS names its levels, outermost first, as `diogenes--browser-labels\=' holds
them; without them every level takes a stop, which is right for most and wrong
for the pages.

    (4 208)      with (\"book\" \"verse\")                  -> 4.208
    (1053a 15)   with (\"Bekker page\" \"line\")             -> 1053a15
    (246a 4 2)   with (\"Stephanus page\" \"section\" \"line\") -> 246a4.2
    (25)         with (\"verse\")                          -> 25

The elements may be numbers or symbols -- `1053a\=' is a symbol -- so each is
printed rather than formatted as a number."
  (let ((parts nil))
    (cl-loop for element in citation
             for index from 0
             for label = (nth index labels)
             do (push (format "%s" element) parts)
             ;; A stop BEFORE the next element, unless this level runs on.
             when (and (nth (1+ index) citation)
                       (not (diogenes--citation-runs-on-p label)))
             do (push "." parts))
    (apply #'concat (nreverse parts))))

(defun diogenes-citation-to-key (citation)
  "CITATION as a string that can be turned back into CITATION.
A stop between every level, whatever the levels are called:

    (1053a 15)     -> \"1053a.15\"
    (10 20 2 1)    -> \"10.20.2.1\"
    (25)           -> \"25\"

REVERSIBLE, which is the whole point and the reason it ignores the conventions
that `diogenes-citation-to-string\=' honours.  `1053a15\=' is how a reader writes
Aristotle and cannot be read back: nothing in the string says where the page
ends and the line begins, and knowing would mean knowing the work\='s levels
before parsing the citation that identifies the work.  `1053a.15\=' says.

So: this for anything that must be read again -- a link, a stored reference, an
argument to a command -- and the other for anything a person reads."
  (mapconcat (lambda (element) (format "%s" element)) citation "."))

(defun diogenes-citation-from-key (key)
  "KEY, as `diogenes-citation-to-key\=' wrote it, back to a citation.
The elements come back as strings.  Diogenes gives some as numbers and some as
symbols -- `1053a\=' is a symbol -- and it takes strings where it takes a passage
at all, `diogenes--select-passage\=' collecting them with `read-string\='; so
strings are what a caller wants and no attempt is made to guess which were
numbers."
  (and key (split-string key "\\." t)))

(defun diogenes-browser-citation-at (&optional position)
  "The citation of the line at POSITION, or at point.
Nil where there is none -- a header line, a blank, the space between passages.
Searches BACKWARD from there if the line itself has none, a citation belonging
to the lines that follow it rather than sitting on every one."
  (save-excursion
    (when position (goto-char position))
    (or (get-text-property (point) 'cit)
        (let ((match (text-property-search-backward 'cit)))
          (and match (prop-match-value match))))))

(defun diogenes-browser-citation-interval ()
  "The citations bounding the region, or the one at point.
Returns (START . END), with END nil where there is no region: a reader
referring to a single line wants that line, and one who has marked a passage
wants its extent.

This is what the buffer can say about WHERE IT IS.  It keeps no record of that
-- paging is the Perl process\='s business and the buffer is told only what to
display -- but every line carries its citation as a text property, so the
position is readable from the text even though it is not remembered."
  (if (use-region-p)
      (cons (diogenes-browser-citation-at (region-beginning))
            (diogenes-browser-citation-at (max (region-beginning)
                                               (1- (region-end)))))
    (cons (diogenes-browser-citation-at) nil)))

(defun diogenes-browser-reference ()
  "Everything needed to name, and to reopen, the passage in this buffer.
A plist: `:corpus\=', `:author\=', `:work\=', `:from\=' and `:to\=' -- the last two
being citations, and `:to\=' nil unless a region is marked.

The corpus, author and work are what `diogenes-browse-tlg\=' and its siblings
take, so a reference is enough to open the work again; `:from\=' says where in it.
Nil in a buffer that is not a browser, there being nothing to refer to."
  (when (derived-mode-p 'diogenes-browser-mode)
    (let* ((interval (diogenes-browser-citation-interval))
           (from (car interval))
           (to (cdr interval))
           (labels diogenes--browser-labels))
      (list :corpus diogenes--browser-corpus
            :author diogenes--browser-author
            :work diogenes--browser-work
            :labels labels
            :from from
            :to to
            ;; TWO renderings, for two jobs.  `:text' is for a reader and
            ;; follows the conventions: `1053a15'.  `:key' is for anything that
            ;; must read it back and puts a stop between every level:
            ;; `1053a.15'.  Neither can do the other's work -- the conventional
            ;; form is not reversible, and the reversible form is not what
            ;; anyone writes in a note.
            :text (when from
                    (concat (diogenes-citation-to-string from labels)
                            (when to
                              (concat "-" (diogenes-citation-to-string
                                           to labels)))))
            :key (when from
                   (concat (diogenes-citation-to-key from)
                           (when to
                             (concat "-" (diogenes-citation-to-key to)))))))))

(defun diogenes--browse-work (options passage)
  "Function that browses a work from the Diogenes Databases.

Passage has to be a list of strings containing the four digit
number of the author and the number of the work."
  (with-current-buffer (diogenes--start-perl
			"browser"
			(diogenes--browse-interactively-script options passage)
			#'diogenes--browser-filter)
    (diogenes-browser-mode)
    (setq diogenes-browser-first-insertion t)
    (setq diogenes--browser-language
	  (pcase (plist-get options :type)
	    ("tlg" "greek")
	    ("phi" "latin")))
    ;; What this buffer is reading.  PASSAGE begins with the author and the
    ;; work, whatever else follows: `diogenes--browse-database' builds it as
    ;; `(nconc (list author work) passage)'.
    (setq diogenes--browser-corpus (plist-get options :type))
    (setq diogenes--browser-author (car passage))
    (setq diogenes--browser-work (cadr passage))
    (setq diogenes--browser-passage (cddr passage))
    ;; And what the levels are called, which is what lets a citation be
    ;; written the way a reader would write it.  Guarded: a work whose labels
    ;; Perl will not give is still browsable, and a reference from it renders
    ;; plainly rather than not at all.
    (setq diogenes--browser-labels
          (ignore-errors
            (diogenes--get-work-labels (list :type (plist-get options :type))
                                       (list (car passage) (cadr passage)))))
    (current-buffer)))

(defun diogenes--browse-database (type &optional author work)
  "Select a specific passage in a work from a diogenes database for browsing.
Uses the Diogenes Perl module."
  (let* ((author (or author
		     (diogenes--select-author-num (list :type type))))
	 (work (or work
		   (diogenes--select-work-num (list :type type)
					      author)))
	 (passage (when (y-or-n-p "Specify passage? ")
		    (diogenes--select-passage (list :type type)
					      author
					      work))))
    (diogenes--browse-work (list :type type) (nconc (list author work)
						    passage))))


;;;; --------------------------------------------------------------------
;;;; DUMPER
;;;; --------------------------------------------------------------------

(defun diogenes--dump-from-database-sentinel (process event)
 "Sentinel for the Diogenes Dumper. Its main function is to
initialize post-processing after termination."
 (with-current-buffer (process-buffer process)
   (pcase event
     ("finished\n"
      (goto-char (point-max))
      (set-mark (point))
      (re-search-backward "^[[:alpha:]]+")
      (beginning-of-line)))))

(defun diogenes--dump-work (options passage)
  "Function that dumps a work from the Diogenes Databases.

Passage has to be a list of strings containing the four digit
number of the author and the number of the work."
  (diogenes--start-perl "dump"
			(diogenes--browser-script
			 (append options '(:browse-lines 100000000))
			 passage)
			nil
			#'diogenes--dump-from-database-sentinel))
;; $query->{browser_multiple} = 100000000

(defun diogenes--dump-from-database (type &optional author work)
  "Dump a work from a Diogenes database in its entirety.
Uses the Diogenes Perl module."
  (let* ((author (or author
		     (diogenes--select-author-num `(:type ,type))))
	 (work (or work
		   (diogenes--select-work-num `(:type ,type)
					      author))))
    (diogenes--dump-work `(:type ,type) (list author work))))

(provide 'diogenes-browser)

;;; diogenes-browser.el ends here

