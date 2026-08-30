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

