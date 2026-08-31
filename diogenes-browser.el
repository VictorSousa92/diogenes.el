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
      "<-- back" "Load the previous page (C-c C-p)"
      #'diogenes-browser-backward)
     "   "
     (diogenes-browser--header-button
      "forward -->" "Load the next page (C-c C-n)"
      #'diogenes-browser-forward)
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
		(t (recenter -1 t))))))))))

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

