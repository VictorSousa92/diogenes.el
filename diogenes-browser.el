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

(defcustom diogenes-browser-page-margin 1
  "Lines held back when paging, beyond what wrapping accounts for.
The browser asks Diogenes for a number of TEXT lines, and what a reader sees is
SCREEN lines: a verse with its citation before it wraps in a narrow window, so
forty lines of text can want sixty lines of window.  How much wrapping the
current text does is measured rather than guessed -- see
`diogenes-browser--lines-to-request\=' -- and this is the margin on top of it,
for the line the measurement cannot foresee."
  :type 'integer
  :group 'diogenes)

(defun diogenes-browser--lines-to-request ()
  "How many lines to advance, so that nothing goes past unseen.

The number Diogenes is sent is an ADVANCE, and the page it answers with is its
own size rather than that number: a window 52 lines tall asked for 49 and was
given 34, and fifteen lines were skipped at every press.

So the measure is WHAT WAS SHOWN -- the lines now in the buffer, less the
overlap -- which cannot skip anything by construction.  The window is consulted
only for the first page, there being nothing yet to count, and then divided by
how much the text wraps, since a wrapped line takes more of the window than it
gives of the text.
The window\='s height less the overlap, divided by how much the text now in the
buffer wraps: a page whose lines take an average of one and a half screen lines
each should be asked for two thirds as many.

Measured from the buffer itself, so it follows the window\='s width, the font, and
the length of the citations this work carries, none of which can be known in
advance.  An empty buffer -- the first page -- has nothing to measure and is
asked for the plain height."
  (let ((shown (count-lines (point-min) (point-max))))
    (if (> shown 1)
        ;; A page is what a page turned out to be.
        (max 1 (- shown next-screen-context-lines
                  diogenes-browser-page-margin))
      ;; The first page: the window, less what wrapping will cost.
      (let* ((height (max 1 (- (floor (window-screen-lines))
                               next-screen-context-lines
                               diogenes-browser-page-margin)))
             (screen-lines (count-screen-lines (point-min) (point-max)))
             (factor (if (and (> shown 0) (> screen-lines shown))
                         (/ (float screen-lines) shown)
                       1.0)))
        (max 1 (floor (/ height factor)))))))

(defun diogenes-browser-forward ()
  "Load the next page from the Diogenes browser.
Takes no prefix argument: how much to advance is what fills the window once,
which `diogenes-browser--lines-to-request\=' works out from the window\='s height
and how much the text is wrapping."
  (interactive)
  (setq diogenes--browser-backwards nil)
  (goto-char (point-max))
  (diogenes--send-cmd-to-browser
   (concat (number-to-string (diogenes-browser--lines-to-request))
	   "n")))

(defun diogenes-browser-backward ()
  "Load the previous page from the Diogenes browser.
Takes no prefix argument, as `diogenes-browser-forward\=' takes none."
  (interactive)
  (setq diogenes--browser-backwards t)
  (goto-char (point-min))
  (diogenes--send-cmd-to-browser
   (concat (number-to-string (diogenes-browser--lines-to-request))
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

It was off for a while, having shipped broken.  The first version read the wrong
text property -- the citation printed at the head of a line is marked
`diogenes-citation\=', not `cit\=', which is on the text -- and so took the
citation's own digits for the second half of the word: `captan-\=' followed by
`10.20.2.4 tem spiritus liquit\=' was looked up as `captan10\='.  With the citations
hidden it was worse: the loop that skipped them could not advance and Emacs
hung.

Both are mended and confirmed in use, in the Greek and the Latin both --
`captantem\=' in Seneca, `singulos\=' in a PHI text whose citation has four levels
-- so the default is on.  A reader meeting a divided word wants the word, and
having to know that an option exists before `C-c C-c\=' will find it is a poor
bargain for a fault that no longer happens.

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
    ;; Past the citation printed at the head of the line.  `diogenes-citation'
    ;; is the property that marks it -- `cit' is on the TEXT, carrying the
    ;; citation the words belong to, which is a different thing and the one this
    ;; first read.  Reading it meant the loop exited at once and the citation's
    ;; digits were taken for the word: `captan-' and `10.20.2.4 tem spiritus'
    ;; became `captan10'.
    ;;
    ;; BOUNDED, and that matters more than the property.  A loop whose progress
    ;; depends on `next-single-property-change' advancing should never be
    ;; written without a floor: with the citations hidden it did not advance,
    ;; and Emacs hung.  Ten steps is far more than a citation needs and is not
    ;; forever.
    (let ((steps 0)
          (limit (line-end-position)))
      (while (and (< steps 10)
                  (< (point) limit)
                  (get-text-property (point) 'diogenes-citation))
        (let ((next (next-single-property-change (point) 'diogenes-citation
                                                 nil limit)))
          ;; Not advancing is the hang: step over one character rather than
          ;; standing still, and let the count end it if even that fails.
          (goto-char (if (and next (> next (point))) next (1+ (point)))))
        (setq steps (1+ steps))))
    (skip-chars-forward " \t")
    ;; And past a citation the PROPERTY does not cover.  The loop above skips
    ;; what the browser marked `diogenes-citation'; a text may print its own
    ;; reference at the head of the line unmarked -- `pes-' followed by
    ;; `8.1.2.2 simum est' -- and there the loop stopped at the first digit and
    ;; `8' was taken for the second half.  Stripped of its non-letters by
    ;; `diogenes-browser-lookup' that is `pes', which parses, which is why it
    ;; looked like no bug at all: the reader gets `pēs, masc nom/voc sg' for a
    ;; word that is `pessimum'.
    ;;
    ;; Only a reference SHAPED like one -- digits and dots, and whitespace
    ;; after it.  No text divides a word so that the remainder begins with a
    ;; digit, so nothing here can eat a real second half.  Bounded, like the
    ;; loop above: three is more than any citation needs.
    (let ((steps 0))
      (while (and (< steps 3)
                  (looking-at "[0-9]+\\(?:\\.[0-9]+\\)*[ \t]+"))
        (goto-char (match-end 0))
        (setq steps (1+ steps))))
    ;; And nothing to join to where the rest of the line is a citation and no
    ;; word follows it.
    (when-let* ((tail (bounds-of-thing-at-point 'word))
                ;; ON THIS LINE.  `bounds-of-thing-at-point' crosses a
                ;; newline, so at the end of a line that is nothing but a
                ;; citation it would reach down to the line after and join a
                ;; word two lines from the hyphen.
                ((< (car tail) (line-end-position)))
                (second (buffer-substring-no-properties (car tail) (cdr tail))))
      ;; A second half that is all digits is a citation, not a word: no text
      ;; divides a word so that the remainder is a number.
      ;;
      ;; The regex was written `"\\\\`[0-9.]+\\\\'"' -- four backslashes, the
      ;; docstring convention leaking into code -- so the string held `\\`'
      ;; and the pattern looked for a literal backslash before a backtick.
      ;; It could not match a number, and the guard had never once fired.
      (unless (string-match-p "\\`[0-9.]+\\'" second)
        (concat first-half second)))))

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
  "Lookup word at point, joined with its other half where the text divided it.
`C-c C-c\=' in the browser is this command and not the ordinary lookup, so the
joining had to be asked for here as well: hooking it into
`diogenes--word-at-point-for-lookup\=' left this key -- the one a reader actually
presses on a passage -- calling `thing-at-point\=' as before, and looking up
`captan\=' where the word is `captantem\='."
  (interactive)
  (funcall (intern (concat "diogenes-parse-and-lookup-"
			   diogenes--browser-language))
	   (replace-regexp-in-string
	    "[^[:alpha:]]" ""
	    (or (and diogenes-browser-join-broken-words
		     (diogenes-browser--word-at-point-joined))
		(thing-at-point 'word)))))

;;; Browser Mode
(defcustom diogenes-browser-mouse-keys nil
  "Mouse gestures that look a word up, as (GESTURE . COMMAND).
Nil by default and off: clicking a word and getting a dictionary entry is not
what a reader expects of an Emacs buffer, and this is a package other people
use.

The mouse-1 gesture is safe to take.  Emacs fires it only on a click in place;
a drag is drag-mouse-1, so marking a passage still works, which matters because
a marked region is how a stretch of lines is named.

Any gesture will do and any command.  Point is moved to the click first,
whatever the command.  Call diogenes-browser-install-mouse-keys after changing
this, or restart."
  :type '(alist :key-type (string :tag "Gesture")
                :value-type (function :tag "Command"))
  :group 'diogenes)

(defun diogenes-browser--at-click (command)
  "COMMAND wrapped so that it acts on the word clicked.
Point does not follow a click of its own accord: mouse-1 ordinarily runs
mouse-drag-region, and that is what moves point.  Binding the gesture to
something else takes it away, so a command would look a word up where point
already was -- one clicks on a word and gets an entry for whatever one was
reading before.

Wrapped rather than asking each command to take an event, so that any command a
reader names works unchanged."
  (lambda (event)
    (interactive "e")
    (mouse-set-point event)
    (call-interactively command)))

;;;###autoload
(defun diogenes-browser-install-mouse-keys ()
  "Bind the gestures in diogenes-browser-mouse-keys in the browser.
Called at load and again after changing the option."
  (interactive)
  (when (boundp 'diogenes-browser-mode-map)
    (dolist (cell diogenes-browser-mouse-keys)
      (when (and (car cell) (cdr cell))
        (keymap-set diogenes-browser-mode-map (car cell)
                    (diogenes-browser--at-click (cdr cell)))))))

(defcustom diogenes-browser-header-line t
  "Whether the browser carries a header line of its own.

    <-- back    forward -->    go to...    Plato, Cratylus

Clickable, and always visible: a header line does not scroll with the text, and
the browser replaces its whole contents on every page, so anything written INTO
the buffer would be swept away with it.  Which is why this is a header and not a
row of widgets at the foot, as the application has.

Nil for no header, and the keys do the same work: `C-c C-n\=' and `C-c C-p\=' page,
and `diogenes-browser-goto-passage\=' asks where to go."
  :type 'boolean
  :group 'diogenes)

(defface diogenes-browser-header-button
  '((t :inherit link))
  "Face for the clickable parts of the browser\='s header line."
  :group 'diogenes)

(defun diogenes-browser--knows-its-work-p ()
  "Whether this browser records which work it is showing.
`diogenes--browser-corpus\=' and its fellows come with the passage reference; a
version without that has no such variables, so they are asked for with `boundp\='
before they are read.  Everything that needs to name the work -- the header, and
`go to\=' -- asks this first."
  (and (boundp 'diogenes--browser-corpus)
       (boundp 'diogenes--browser-author)
       (boundp 'diogenes--browser-work)
       diogenes--browser-corpus
       diogenes--browser-author
       diogenes--browser-work))

(defvar-local diogenes--browser-page-lines nil
  "How many lines the first page of this browser held.
The number to ask for when a page is turned: Diogenes chose the size of the
first page, it fitted the window, and what it held can be counted -- where the
window\='s own height cannot account for the three lines of header printed with
every fetch, nor for the lines that wrap because a citation precedes them.

Set once, when the first page arrives, and not again: a page that REPLACES
another must not grow, and counting what is shown each time made it grow -- `C-c
C-n\=' adds to the buffer, so thirty-four lines became fifty-nine and every press
asked for more than the last.")

(defvar-local diogenes--browser-replace nil
  "Whether the next text to arrive should replace what is in the buffer.
Set by the paging buttons, which turn the page where `C-c C-n\=' and `C-c C-p\='
add to it, and read by the filter.

A FLAG and not an `erase-buffer\=' in the command, because at the end of a work
Diogenes answers with nothing: a buffer emptied when the button was pressed
would leave a reader with neither the next page nor the one they were reading.
The filter erases when it has something to put there.")

(defun diogenes-browser--page-size ()
  "How many lines a page is, for turning one.
The WINDOW\='s height, less `diogenes-browser-page-margin\=', and no overlap: a page
that is REPLACED wants the lines after the ones you read, not two of them again.

Not what is shown, which was the first answer and made the request GROW: `C-c
C-n\=' adds to the buffer, so thirty-four lines became fifty-nine, every press
asked for more than the last, and the start or the end of a work came sooner each
time.  A window does not drift."
  ;; What the FIRST page held, which Diogenes sized and which fitted.  Neither
  ;; the window's height nor the lines now shown will do: the height ignores the
  ;; three lines of header printed with every fetch and the lines that wrap
  ;; behind a citation, and the count of what is shown grows, `C-c C-n' adding
  ;; to the buffer until every press asked for more than the last.
  (max 1 (or diogenes--browser-page-lines
             (- (floor (window-screen-lines))
                diogenes-browser-page-margin))))

(defun diogenes-browser-page-forward ()
  "Show the page after this one, in place of it.
Where `diogenes-browser-forward\=' adds the next lines below what is there, this
replaces: the same number of lines, taken from after what is shown.  Nothing is
lost where there is no more text -- the buffer is emptied only when there is
something to put in it."
  (interactive)
  (setq diogenes--browser-backwards nil
        diogenes--browser-replace t
        diogenes-browser-first-insertion t)
  (goto-char (point-max))
  (diogenes--send-cmd-to-browser
   (concat (number-to-string (diogenes-browser--page-size)) "n")))

(defun diogenes-browser-page-backward ()
  "Show the page before this one, in place of it.
The counterpart of `diogenes-browser-page-forward\='."
  (interactive)
  (setq diogenes--browser-backwards t
        diogenes--browser-replace t
        diogenes-browser-first-insertion t)
  (goto-char (point-min))
  (diogenes--send-cmd-to-browser
   (concat (number-to-string (diogenes-browser--page-size)) "p")))

(defun diogenes-browser-goto-passage (&optional passage)
  "Open this work at PASSAGE, asking for it when not given.
A citation as the work numbers itself -- `384a\=', `1.5.2\=', `1053a15\=' -- and not
a line of the buffer: the browser shows a stretch of a text, and where a reader
wants to be is a place in the WORK.  The levels this work uses are named in the
prompt where the corpus told us them.

The same Perl request `diogenes-open-passage\=' makes, so the reader arrives with
the passage at the top rather than paged to."
  (interactive)
  (unless (derived-mode-p 'diogenes-browser-mode)
    (user-error "Not in a Diogenes browser"))
  (unless (diogenes-browser--knows-its-work-p)
    (user-error
     (concat "This browser does not record which work it is showing"
             " -- the passage reference is not in this version")))
  (let* ((labels (and (boundp 'diogenes--browser-labels)
                      diogenes--browser-labels))
         (prompt (if labels
                     (format "Go to (%s): "
                             (string-join (mapcar #'string-trim labels) ", "))
                   "Go to (levels separated by full stops): "))
         (answer (or passage (read-string prompt)))
         (levels (split-string (string-trim answer) "[.: ]+" t)))
    (unless levels
      (user-error "No passage given"))
    ;; Outermost level first, as Diogenes takes them.
    (diogenes-open-passage diogenes--browser-corpus
                           diogenes--browser-author
                           diogenes--browser-work
                           levels)))

(defun diogenes-browser--header-button-runner (command)
  "COMMAND wrapped to run in the window whose header line was clicked.
A header-line click does not select the window, so a command run from one acts
on whatever buffer happened to be current: the paging buttons set their
buffer-local flags in another buffer, the filter read nil for them in the
browser, and the text arrived at the end as though `forward\=' had been pressed.

The event says which window it came from, and that is the one to work in."
  (lambda (event)
    (interactive "e")
    (let ((window (posn-window (event-start event))))
      (if (window-live-p window)
          (with-selected-window window
            (call-interactively command))
        (call-interactively command)))))

(defun diogenes-browser--header-button (label help command)
  "LABEL as a clickable piece of a header line, running COMMAND."
  (let ((map (make-sparse-keymap))
        (command (diogenes-browser--header-button-runner command)))
    ;; `header-line-format\=' takes its clicks through `mouse-1\=' on the string
    ;; itself; `follow-link\=' lets a reader who has `mouse-1-click-follows-link\='
    ;; use a plain click, as they would on any other button.
    (keymap-set map "<header-line> <mouse-1>" command)
    (keymap-set map "<header-line> <mouse-2>" command)
    (propertize label
                'face 'diogenes-browser-header-button
                'mouse-face 'highlight
                'help-echo help
                'follow-link t
                'keymap map)))

(defun diogenes-browser-header-line ()
  "The browser\='s header line: where to go, and what is being read.
Built afresh each time Emacs draws it, so it follows the buffer without anything
having to remember to update it -- which matters, the contents being replaced by
a Perl process on every page."
  (when diogenes-browser-header-line
    (concat
     " "
     (diogenes-browser--header-button
      "<-- back" "Turn back a page, replacing this one"
      #'diogenes-browser-page-backward)
     "   "
     (diogenes-browser--header-button
      "forward -->" "Turn forward a page, replacing this one"
      #'diogenes-browser-page-forward)
     ;; Only where the browser records what it is showing.  Elsewhere there is
     ;; nothing to open, and a button that answers a click with an explanation
     ;; is worse than no button.
     (if (diogenes-browser--knows-its-work-p)
         (concat "   "
                 (diogenes-browser--header-button
                  "go to..." "Open this work at a citation"
                  #'diogenes-browser-goto-passage))
       "")
     ;; And what is being read, where the browser knows: a reader who has
     ;; several open should not have to look at the text to tell which is which.
     (if (diogenes-browser--knows-its-work-p)
         (format "   %s %s/%s"
                 diogenes--browser-corpus
                 diogenes--browser-author
                 diogenes--browser-work)
       ""))))

(defvar diogenes-browser-mode-map
  (let ((map (nconc (make-sparse-keymap) text-mode-map)))
    ;; Overrides of movement keys.  A remap catches the command NAMED and
    ;; nothing else: under evil in normal state the arrows are
    ;; `evil-previous-line' and `evil-next-line', so remapping `previous-line'
    ;; alone left a reader unable to page by arrow under Doom, where the browser
    ;; is in normal state -- while Spacemacs and a plain Emacs worked, having it
    ;; in Emacs state where the arrows ARE `previous-line'.
    ;;
    ;; The visual-line pair with them, being what the arrows run where
    ;; `visual-line-mode' is on; and `gg' and `G', which should page as `M-<'
    ;; and `M->' do.
    (dolist (pair '((previous-line             . backward-line)
                    (next-line                 . forward-line)
                    (evil-previous-line        . backward-line)
                    (evil-next-line            . forward-line)
                    (evil-previous-visual-line . backward-line)
                    (evil-next-visual-line     . forward-line)
                    (beginning-of-buffer       . beginning-of-buffer)
                    (end-of-buffer             . end-of-buffer)
                    (evil-goto-first-line      . beginning-of-buffer)
                    (evil-goto-line            . end-of-buffer)))
      (keymap-set map (format "<remap> <%s>" (car pair))
                  (intern (format "diogenes-browser-%s" (cdr pair)))))
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
  ;; A line of its own, above the text: see
  ;; `diogenes-browser-header-line'.
  (setq header-line-format '(:eval (diogenes-browser-header-line)))
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

(defun diogenes--browser-remove-duplicate-header (header)
  "Take out any header already in the buffer whose text is HEADER's.
Called before inserting one, so that paging leaves a passage with a single
header at its top rather than one at every place a fetch began.

Compared by TEXT, not by position: a reader who pages out of one work and into
another wants both headers, and only the repetition of one header is the
mistake."
  ;; TRIMMED before comparing.  The backwards path inserts a newline before the
  ;; header it is about to add, so one copy begins with a newline and the other
  ;; does not -- and `equal' on the two texts is then false for two copies of
  ;; one header, which is the only case this function exists to catch.  Nothing
  ;; else distinguishes them: the author, the work, the edition are the same
  ;; string.
  (let ((wanted (string-trim (substring-no-properties header)))
        (case-fold-search nil))
    (save-excursion
      (goto-char (point-min))
      (let (match)
        (while (setq match (text-property-search-forward 'diogenes-header t #'eq))
          (let ((start (prop-match-beginning match))
                (end (prop-match-end match)))
            (when (equal (string-trim
                          (buffer-substring-no-properties start end))
                         wanted)
              (delete-region start end)
              ;; The search\='s idea of where it is went with the text.
              (goto-char (min start (point-max))))))))))

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
	 ;; NOTHING THERE is a boundary and not an error.  Diogenes answers a
	 ;; request that runs past the start or the end of a work with a header
	 ;; and no lines, and a `error' here reached the reader as
	 ;; `error in process filter' -- for the ordinary case of having asked to
	 ;; go back further than the work goes.
	 (unless lines
	   (setq diogenes--browser-replace nil)
	   (message "Nothing %s this passage"
		    (if (and (boundp 'diogenes--browser-backwards)
			     diogenes--browser-backwards)
			"before" "after")))
	 (when lines
	 (cond ((and (boundp 'diogenes--browser-backwards)
		     diogenes--browser-backwards)
		(cond (header (goto-char (point-min))
			      (newline)
			      (goto-char (point-min)))
		      (t (or (text-property-search-forward 'diogenes-header)
			     (goto-char (point-min))))))
	       (t (goto-char (point-max))))
	 ;; A page turned rather than added to: the buffer is emptied HERE,
	 ;; where there is text to put in it, and not when the button was
	 ;; pressed.  See `diogenes--browser-replace'.
	 (when diogenes--browser-replace
	   (setq diogenes--browser-replace nil)
	   (let ((inhibit-read-only t))
	     (erase-buffer))
	   (goto-char (point-min)))
	 (when header
	   ;; A HEADER ALREADY IN THE BUFFER, saying the same thing, is taken
	   ;; out.  Diogenes prints the header with every stretch it fetches, and
	   ;; paging backwards inserts the new stretch above the old: so the
	   ;; header that was at the top ends up in the middle of the text, three
	   ;; lines of `Plato Phil., Cratylus' between one verse and the next.
	   ;;
	   ;; Only where it says the SAME thing.  A reader who has paged out of
	   ;; one work and into another wants both headers -- that is the header
	   ;; doing its job -- and comparing the text is how to tell the two
	   ;; cases apart.
	   (diogenes--browser-remove-duplicate-header
	    (diogenes--browser-format-header header))
	   (insert (diogenes--browser-format-header header)))
	 ;; The size of the first page, for turning one later.  Set once: see
	 ;; `diogenes--browser-page-lines'.
	 (unless diogenes--browser-page-lines
	   (setq diogenes--browser-page-lines (length lines)))
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
		(t (recenter -1 t))))))))))

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

(defun diogenes-citation-interval-from-key (key)
  "KEY back to (FROM . TO), TO nil where KEY names a single citation.
The inverse of what `diogenes-browser-reference\=' puts in `:key\='.

Split on the HYPHEN first and each half on stops after: splitting the whole of
`2.2-2.5\=' on stops gave `(\"2\" \"2-2\" \"5\")\=', the hyphen swallowed into an
element and the passage unopenable.  `diogenes-citation-from-key\=' reads one
citation and was handed two, which is the sort of fault that shows only when
something tries to read back what was written -- and a link that cannot be read
back is a dead link."
  (when key
    (let* ((halves (split-string key "-" t))
           (from (diogenes-citation-from-key (car halves)))
           (to (and (cdr halves)
                    (diogenes-citation-from-key (cadr halves)))))
      (cons from to))))

(defun diogenes-open-passage (corpus author work &optional passage)
  "Open WORK of AUTHOR in CORPUS, at PASSAGE, asking nothing.
CORPUS is `tlg\=', `phi\=' and the rest; AUTHOR and WORK are the numbers as
strings; PASSAGE is a list of strings, as `diogenes-citation-from-key\=' returns,
or nil for the beginning of the work.

PUBLIC, and non-interactive, which is the point of it.  `diogenes-browse-tlg\='
and its siblings ask `Specify passage?\=' and then for each level in turn --
right for a reader choosing where to go, and no use to anything holding a
reference already.  A link that asked four questions before opening would not be
a link.

It is also the boundary a separate package should call.  `diogenes--browse-work\='
is private: the two hyphens say that its name and its arguments are nobody
else\='s business, and a package outside this one calling it would break silently
on a rename."
  (diogenes--browse-work (list :type corpus)
                         (nconc (list author work)
                                (copy-sequence passage))))

(defun diogenes-open-reference (reference)
  "Open the passage REFERENCE names.
REFERENCE is what `diogenes-browser-reference\=' returns, or the same plist read
back from wherever it was stored -- a link, a note.  `:key\=' is used in
preference to `:from\=', being the form that survives writing down."
  (let* ((key (plist-get reference :key))
         (interval (and key (diogenes-citation-interval-from-key key)))
         (from (or (car interval)
                   (mapcar (lambda (element) (format "%s" element))
                           (plist-get reference :from)))))
    (diogenes-open-passage (plist-get reference :corpus)
                           (plist-get reference :author)
                           (plist-get reference :work)
                           from)))

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

(defcustom diogenes-abbreviation-overrides nil
  "Abbreviations to use instead of the generated table\='s.
An alist keyed as the table is -- `((\"tlg\" \"0086\") . \"Aristot.\")\=' for an
author, `((\"tlg\" \"0086\" \"025\") . \"Met.\")\=' for a work -- and consulted first,
so an entry here wins.

Two uses.  A reader who prefers another convention to LSJ\='s: `Aristot.\=' for
`Arist.\=', or an English title where the dictionaries give a Latin one.

And the handful of rows the extraction gets wrong, which are wrong in ways no
rule catches.  `phi 0012\=' is Homer, whose number that is in the TLG and not the
PHI, from a mistagged citation in Lewis & Short -- harmless, there being no such
author to browse.  `phi 0474/065\=' reads `Horte\=', the Hortensius truncated in
the source.  Four such rows in a thousand when this was written, and each is
one line to correct here rather than a reason to distrust the rest."
  :type '(alist :key-type (repeat string) :value-type string)
  :group 'diogenes)

(defun diogenes-citation-abbreviation (corpus author &optional work)
  "How the dictionaries cite this author, or this work of theirs.
Returns (AUTHOR-ABBREV . WORK-ABBREV), either of which may be nil.

`Arist.\=' and `Metaph.\=', `Hom.\=' and `Il.\=', `Verg.\=' and `A.\=' -- the forms LSJ
and Lewis & Short use, taken from the dictionaries themselves rather than from
their printed front matter, which names no numbers.  See
`tools/extract-abbreviations.py\='.

Nil for a text neither dictionary cites, which is most of the two corpora: the
table covers some five hundred works of the TLG and two hundred and seventy of
the PHI, being the texts the lexicographers had occasion to quote."
  (let ((look (lambda (key)
                (or (cdr (assoc key diogenes-abbreviation-overrides))
                    (and (boundp 'diogenes-abbreviations)
                         (gethash key diogenes-abbreviations))))))
    (cons (funcall look (list corpus author))
          (and work (funcall look (list corpus author work))))))

(defun diogenes-reference-to-string (reference)
  "REFERENCE written as a scholar would write it.
`Arist. Metaph. 1053a15\=', `Hom. Il. 9.1\=', `Verg. A. 4.208\='.

Falls back by degrees, each step giving up something and none failing outright:
the work\='s abbreviation where the dictionaries have one, the author\='s alone
where they name him but not it, and the numbers where they name neither.  A
reader who cites a text no lexicographer quoted gets `tlg 2632/001 3.4\=', which
is at least unambiguous."
  (let* ((corpus (plist-get reference :corpus))
         (author (plist-get reference :author))
         (work (plist-get reference :work))
         (text (plist-get reference :text))
         (pair (diogenes-citation-abbreviation corpus author work))
         (author-abbrev (car pair))
         (work-abbrev (cdr pair)))
    (string-join
     (delq nil
           (list (cond ((and author-abbrev work-abbrev)
                        (concat author-abbrev " " work-abbrev))
                       (author-abbrev)
                       (t (format "%s %s/%s" corpus author work)))
                 text))
     " ")))

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

;; `:citation' is added after the fact, `diogenes-reference-to-string' needing
;; the reference it goes into.  A separate call rather than a fourth key, so
;; that a caller wanting only the numbers pays nothing for the abbreviations.

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

