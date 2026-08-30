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

(defcustom diogenes-browser-page-lines nil
  "How many lines a page shows, and so when a page is turned.
Nil for as many as the first page Diogenes sent, which it sized to the window --
that being the honest measure, since the window\='s own height cannot account for
the three lines of header printed with every fetch nor for the lines that wrap
behind a citation.

A number to say it outright, which is worth doing where a reader wants the same
page whatever window the browser happens to be in."
  :type '(choice (const :tag "As long as the first page came" nil)
                 (integer :tag "This many lines"))
  :group 'diogenes)

(defcustom diogenes-browser-add-lines 0.5
  "How much `C-c C-n\=' and `C-c C-p\=' add, as a fraction of a page or a count.

    0.5   half a page, which leaves the other half in view
    1.0   a whole page, the same as the header\='s buttons fetch
    15    fifteen lines, whatever a page happens to be

A FLOAT is a fraction and an INTEGER a count: `1.0\=' is a whole page and `1\=' is
one line.  Write the point where you mean a share of a page.

Of the page `diogenes-browser-page-lines\=' gives, or of the first page Diogenes
sent where that is nil.  TRUNCATED, so a page of 33 halved adds 16 and the halves
meet -- rounding sent .5 up and added one line more than half.

The keys ADD where the header\='s buttons replace: half a page read on into keeps
your place on the screen, which is what they are for."
  :type '(choice (number :tag "A fraction of a page (below 1)")
                 (integer :tag "This many lines (1 or more)"))
  :group 'diogenes)

(defcustom diogenes-browser-turn-keys
  '(("C-c C-<right>" . diogenes-browser-page-forward)
    ("C-c C-<left>" . diogenes-browser-page-backward))
  "Keys that TURN a page, as (KEY . COMMAND).
Turning replaces what is shown; `C-c C-n\=' and `C-c C-p\=' add to it.  Until these
existed a page could only be turned by clicking the header, which is no use to a
reader who does not use a mouse.

`C-c C-<right>\=' and `C-c C-<left>\=' by default.  The arrows are on every
keyboard, where PageDown and PageUp -- `<next>\=' and `<prior>\=', which came
first -- are not, or want a modifier of their own and make the sequence four keys
deep.

And they read well beside the keys that ADD: `C-c C-n\=' and `C-c C-p\=' go along
the text, `C-c C-<right>\=' and `C-c C-<left>\=' turn across it.

Set to nil to bind nothing.

`diogenes-browser-install-turn-keys\=' after changing it, or restart."
  :type '(alist :key-type (string :tag "Key")
                :value-type (function :tag "Command"))
  :group 'diogenes)

;;;###autoload
(defun diogenes-browser-install-turn-keys ()
  "Bind `diogenes-browser-turn-keys\=' in the browser."
  (interactive)
  (when (boundp 'diogenes-browser-mode-map)
    (dolist (cell diogenes-browser-turn-keys)
      (when (and (car cell) (cdr cell))
        (condition-case error
            (keymap-set diogenes-browser-mode-map (car cell) (cdr cell))
          (error (message "Diogenes: cannot bind %s: %s"
                          (car cell) (error-message-string error))))))))

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

(defvar diogenes-browser-key-page-fraction nil
  "Obsolete.  Use `diogenes-browser-add-lines\=', which takes a fraction too.
Read where it is set, so a configuration written against it goes on working.")

(make-obsolete-variable 'diogenes-browser-key-page-fraction
                        'diogenes-browser-add-lines "diogenes.el 2026-08")

(defun diogenes-browser--lines-to-add ()
  "How many lines `C-c C-n\=' and `C-c C-p\=' should ask for.
`diogenes-browser-key-page-fraction\=' of the first page, and never less than
one."
  (let* ((page (or diogenes-browser-page-lines
                   diogenes--browser-page-lines
                   (max 1 (- (floor (window-screen-lines))
                             next-screen-context-lines))))
         ;; The obsolete option still answers where somebody set it.
         (how (or diogenes-browser-key-page-fraction
                  diogenes-browser-add-lines
                  0.5)))
    (max 1 (if (floatp how)
               ;; A FLOAT is a share of a page, an INTEGER a number of lines.
               ;; Not `(< how 1)': that made `1.0' -- a whole page -- into a
               ;; single line.
               ;;
               ;; TRUNCATED and not rounded: 33 halved is 16, and the halves
               ;; meet.  Rounding sent .5 up and added a line more than half.
               (truncate (* how page))
             (truncate how)))))

(defun diogenes-browser-forward ()
  "Add the next half-page to what is shown.
Takes no prefix argument: how much to add is
`diogenes-browser-key-page-fraction\=' of the first page, half of it by
default.  The text already there is kept -- this is for reading on without
losing your place, where the header\='s `forward\=' button turns the page
instead."
  (interactive)
  (setq diogenes--browser-backwards nil)
  (goto-char (point-max))
  (diogenes--send-cmd-to-browser
   (concat (number-to-string (diogenes-browser--lines-to-add))
	   "n")))

(defun diogenes-browser-backward ()
  "Load the previous page from the Diogenes browser.
Takes no prefix argument, as `diogenes-browser-forward\=' takes none."
  (interactive)
  (setq diogenes--browser-backwards t)
  (goto-char (point-min))
  (diogenes--send-cmd-to-browser
   (concat (number-to-string (diogenes-browser--lines-to-add))
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

(defvar-local diogenes--browser-turned nil
  "Whether the text now arriving replaced the buffer rather than adding to it.
Read once, where point is placed: a page that was TURNED has no frontier -- the
whole of it is new -- so there is nothing to mark and the top is where to be.")

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

(defface diogenes-browser-addition-face
  '((t :inherit secondary-selection :extend t))
  "Face for the lines `C-c C-n\=' or `C-c C-p\=' has just added.
`secondary-selection\=' because that is what it is for -- a region marked for a
moment, which every theme styles and none styles loudly.  `:extend\=' so the
marking reaches the window\='s edge rather than the end of each line, several
lines otherwise making a ragged block."
  :group 'diogenes)

(defvar-local diogenes--browser-addition nil
  "The overlay marking what was last added, or nil.")

(defun diogenes-browser--unmark-addition ()
  "Take the marking off what was added.
On `pre-command-hook\=', so the first thing a reader does -- a movement, a
lookup, anything -- clears it."
  (remove-hook 'pre-command-hook #'diogenes-browser--unmark-addition t)
  (when (overlayp diogenes--browser-addition)
    (delete-overlay diogenes--browser-addition))
  (setq diogenes--browser-addition nil))

(defun diogenes-browser--mark-addition (from to backwards)
  "Put point at the frontier of the text between FROM and TO, and mark it.
BACKWARDS says which side the new text came from, and so which side the frontier
is on: reading forward, the join is at FROM and the new lines are below it;
reading back, the join is at TO and the new lines are above.

The marking goes at the next command.  A reader who has just asked for more text
is about to move, so `pre-command-hook\=' is the moment -- and it costs nothing
where a reader sits still and looks."
  (diogenes-browser--unmark-addition)
  (goto-char (if backwards to from))
  ;; The new text on the side it came from: forward shows it below the frontier,
  ;; backward above.
  (condition-case nil
      (recenter (if backwards -2 1))
    (error nil))
  (setq diogenes--browser-addition (make-overlay from to))
  (overlay-put diogenes--browser-addition 'face
               'diogenes-browser-addition-face)
  (overlay-put diogenes--browser-addition 'evaporate t)
  (add-hook 'pre-command-hook #'diogenes-browser--unmark-addition nil t))

(defun diogenes-browser--page-size ()
  "How many lines a page is, for turning one.
What is shown, which is what a page turned out to be -- no overlap: a page that
is REPLACED wants the lines after the ones you read, not two of them again.  The
window\='s height where there is nothing yet to count."
  ;; What the FIRST page held, which Diogenes sized and which fitted.  Neither
  ;; the window's height nor the lines now shown will do: the height ignores the
  ;; three lines of header printed with every fetch and the lines that wrap
  ;; behind a citation, and the count of what is shown grows, `C-c C-n' adding
  ;; to the buffer until every press asked for more than the last.
  (max 1 (or diogenes-browser-page-lines
             diogenes--browser-page-lines
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
    ;; Overrides of movement keys.  A remap catches the command NAMED, and
    ;; nothing else: under evil in normal state the arrows are
    ;; `evil-previous-line' and `evil-next-line', which are not
    ;; `previous-line', so remapping that one alone left a reader unable to
    ;; page by arrow at all -- as happened under Doom, where the browser is in
    ;; normal state, while Spacemacs and a plain Emacs worked because there it
    ;; is in Emacs state and the arrows ARE `previous-line'.
    ;;
    ;; So evil's are remapped beside Emacs's, and the visual-line pair too:
    ;; `evil-next-visual-line' is what the arrows run where `visual-line-mode'
    ;; is on, which a reader may well have.
    (dolist (pair '((previous-line            . backward-line)
                    (next-line                . forward-line)
                    (evil-previous-line       . backward-line)
                    (evil-next-line           . forward-line)
                    (evil-previous-visual-line . backward-line)
                    (evil-next-visual-line     . forward-line)
                    (beginning-of-buffer      . beginning-of-buffer)
                    (end-of-buffer            . end-of-buffer)
                    (evil-goto-first-line     . beginning-of-buffer)
                    (evil-goto-line           . end-of-buffer)))
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
	   (setq diogenes--browser-replace nil
		 diogenes--browser-turned t)
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
	   ;;
	   ;; AFTER the erase above: a page that was turned is emptied first, so
	   ;; there is then nothing to remove and the new header simply goes in.
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
	  (cond (;; A page TURNED, which is tested FIRST: the paging buttons set
		 ;; `diogenes-browser-first-insertion' as well, so a turned page
		 ;; would take that branch and leave this flag standing -- to
		 ;; misfire on the next ADDITION, sending point to the top and
		 ;; marking nothing.
		 ;;
		 ;; The whole buffer is new, so there is no frontier and nothing to
		 ;; mark; the top is where to be.
		 diogenes--browser-turned
		 (setq diogenes--browser-turned nil
		       diogenes-browser-first-insertion nil)
		 (goto-char (point-min)))
		(diogenes-browser-first-insertion
		 (setq diogenes-browser-first-insertion nil)
		 (goto-char pos))
		;; A page ADDED: point to the join, and the new lines marked until
		;; the next keypress.
		(t (diogenes-browser--mark-addition
		    pos (point)
		    (and (boundp 'diogenes--browser-backwards)
			 diogenes--browser-backwards)))))))))))

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
	    ("phi" "latin")))))

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

