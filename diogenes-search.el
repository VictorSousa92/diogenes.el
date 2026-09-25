;;; diogenes-search.el --- Corpus Search for diogenes.el -*- lexical-binding: t -*-

;; Copyright (C) 2024 Michael Neidhart
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

;; This file contains functions for searching the Corpora that Diogenes can read

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'replace)
(require 'transient)
(require 'diogenes-lisp-utils)
(require 'diogenes-user-interface)
(require 'diogenes-lemmata)

(require 'diogenes-forms)
(require 'diogenes-corpora)
(require 'diogenes-perl-interface)       ; diogenes--start-perl and c.
(require 'diogenes-browser)              ; diogenes--browse-work

;; THE BUFFER-LOCAL STATE, DECLARED.  Every one of these was assigned with
;; `setq' and declared nowhere, so the compiler read each reference as a free
;; variable -- some forty warnings from this one cause.  `defvar' and not
;; `defvar-local': the mode calls `make-local-variable' itself, and changing
;; which of them are buffer-local is a decision about behaviour rather than
;; about declarations.
(defvar diogenes--search-active-block nil
  "The block of search results being filled in this buffer.")
(defvar diogenes--search-corpus nil
  "The corpus this buffer's search ran against.")
(defvar diogenes--search-language nil
  "The language of this buffer's search.")



;;----------------------------------------------------------------------
;;;; HELPER FUNCTIONS

;; (defun diogenes--process-pattern (pattern)
;;   "Make sure a pattern is all ASCII. When dealing with greek
;; unicode, convert it to beta code and correctly escape the regex metacharacters."
;;   (save-match-data
;;     (with-temp-buffer
;;       (save-excursion (insert pattern))
;;       (while (re-search-forward "\\cg+" nil t)
;; 	(insert (replace-regexp-in-string "[)(+*\\\\]" "\\\\\\&"
;; 					  (diogenes--utf8-to-beta (match-string 0))))
;; 	(delete-region (match-beginning 0) (match-end 0)))
;;       (buffer-string))))

(defun diogenes--process-pattern (pattern)
  "Dummmy function."
  pattern)

(defun diogenes--probable-corpus-language (type)
  "Determine the probable language of a corpus."
  (pcase type
    ((or "tlg"
	 "ddp")
     "greek")
    ((or "phi") "latin")
    ((or "ins" "chr" "misc") "")
    ("cop" "coptic")
    (_ (error "Language not yet implemented for %s" type))))


;;----------------------------------------------------------------------
;;; Diogenes Search Mode

(defvar diogenes-search-mode-map
  (let ((map (nconc (make-sparse-keymap) text-mode-map)))
    (keymap-set map "RET" #'diogenes-search-browse-passage)
    (keymap-set map "C-c C-c" #'diogenes-search-browse-passage)
    (keymap-set map "<double-mouse-1>" #'diogenes-search-browse-passage)
    (keymap-set map "n" #'diogenes-search-next)
    (keymap-set map "p" #'diogenes-search-previous)
    (keymap-set map "d" #'diogenes-search-delete)
    (keymap-set map "u" #'diogenes-undo)
    (keymap-set map "q" #'diogenes--ask-and-quit)
    ;; (keymap-set map "<mouse-2>" #'diogenes-search-browse-passage)
    ;; (keymap-set map "C-c C-q" #'diogenes-browser-quit)
    ;; ;; Utilities
    ;; (keymap-set map "C-c C--" #'diogenes-browser-remove-hyphenation)
    ;; (keymap-set map "C-c C-+" #'diogenes-browser-reinsert-hyphenation)
    ;; (keymap-set map "C-c C-t" #'diogenes-browser-toggle-citations)
    map)
  "Basic mode map for the Diogenes Search.")

;; Buffer Local Var: diogenes-search-status: body, match, header, nil

(define-derived-mode diogenes-search-mode text-mode "Diogenes Search"
  "Major mode to search Diogenes' databases."
  (make-local-variable 'diogenes--search-active-block)
  (make-local-variable 'diogenes--search-language)
  (make-local-variable 'diogenes--search-corpus)
  (setq buffer-read-only t)
  (visual-line-mode))

(defun diogenes--search-filter (proc string)
  (when (buffer-live-p (process-buffer proc))
    (with-current-buffer (process-buffer proc)
      (let ((eob (and (eobp)
		      (not (bobp))
		      (point)))
	    (inhibit-read-only t))
	(save-excursion
	  (goto-char (process-mark proc))
	  (save-restriction
	    (narrow-to-region (point) (point))
	    (insert string)
	    (set-marker (process-mark proc) (point))
	    (goto-char (point-min))
	    ;; Post-processing
	    (mapc (lambda (subst)
		    (save-excursion
		      (while (re-search-forward (car subst) nil t)
			(replace-match (cdr subst)))))
		  '(("\0" . "")
		    ("~" . "_")))
	    ;; handle header & body blocks
	    (save-excursion
	      (while (not (eobp))
		(let* ((blk diogenes--search-active-block)
		       (start (point))
		       (end (or (cl-case blk
				  ((body)
				   (and (re-search-forward "_\n"
							   nil t)
					(setq diogenes--search-active-block
					      'header)
					(match-end 0)))
				  ((header)
				   (and (re-search-forward "\n\n"
							   nil t)
					(setq diogenes--search-active-block
					      'body)
					(match-end 0))))
				(goto-char (point-max)))))
		  (add-text-properties
		   start end
		   (cl-case blk
		     (header '(header t font-lock-face shr-h2))
		     (body '(body t)))))))))
	(when eob (goto-char (process-mark proc)))))))

;; Entry handling
(defun diogenes--search-get-entry (pos)
  "Get the boundaries of the active passage.
Returns the start position, the boundary between header and body,
and the end as alist."
  (cond ((get-text-property pos 'header)
	 (let* ((start (or (and (> pos (point-min))
				(get-text-property (1- pos) 'body)
				pos)
			   (previous-single-property-change pos 'header)
			   (point-min)))
		(dlm (next-single-property-change pos 'header))
		(end (or (next-single-property-change dlm 'body)
			 (point-max))))
	   (list start dlm end)))
	((get-text-property pos 'body)
	 (let* ((end (or (next-single-property-change pos 'body)
			 (point-max)))
		(dlm (or (and (get-text-property (1- pos) 'header)
			      (1- pos))
			 (previous-single-property-change pos 'header)))
		(start (or (previous-single-property-change dlm 'header)
			   (point-min))))
	   (list start dlm end)))
	(t (error "No entry at point"))))

(defun diogenes--search-get-header-lines (pos)
  "Get the header of the active passage, as s list of lines."
  (let ((entry (diogenes--search-get-entry pos)))
    (split-string (string-trim (buffer-substring (car entry)
						 (cadr entry)))
		  "\n")))

(defun diogenes--search-next-entry (pos)
  "Returns the beginning and end of the entry after POS."
  (let ((entry (diogenes--search-get-entry pos)))
    (if (or (>= (caddr entry) (point-max))
	    (not (get-text-property (1+ (caddr entry))
				    'header)))
	(error "No further entry!")
      (diogenes--search-get-entry (1+ (caddr entry))))))

(defun diogenes--search-previous-entry (pos)
  "Returns the beginning and end of the entry before POS."
  (let ((entry (diogenes--search-get-entry pos)))
    (if (<= (car entry) (point-min))
	(error "No previous entry!")
      (diogenes--search-get-entry (1- (car entry))))))

(defun diogenes--search-delete-entry (pos)
  "Deletes the entry at POS.
This function makes sure that the full citation remains accessible."
  (let ((entry (diogenes--search-get-entry pos))
	(header-lines (diogenes--search-get-header-lines pos))
	(inhibit-read-only t))
    (when-let* ((full-cit (string-match "(\\([0-9]+\\): \\([0-9]+\\)) *$"
					(car header-lines)))
		(next-entry (ignore-errors (diogenes--search-next-entry pos)))
		(next-entry-short-cit (not (string-match "(\\([0-9]+\\): \\([0-9]+\\)) *$"
							 (buffer-substring-no-properties
							  (car next-entry)
							  (cadr next-entry))))))
      (goto-char (cadr next-entry))
      (beginning-of-line -1)
      (delete-region (+ 2 (car next-entry)) (point))
      (mapc (lambda (s) (insert s) (newline))
	    (butlast header-lines)))
    (delete-region (car entry) (caddr entry))
    (ignore-errors (goto-char (cadr (diogenes--search-get-entry (point)))))))


(defun diogenes--search-strip-number (label)
  "LABEL without the number the corpus puts in brackets after it.
`Pro Quinctio (001)\=' is how a work is listed and `Pro Quinctio\=' is how a
result is headed."
  (string-trim (replace-regexp-in-string " *([0-9]+) *\\'" ""
					  (or label ""))))

(defun diogenes--search-loosely (s)
  "S as it is compared: lowercased, and without punctuation."
  (string-join
   (split-string
    (replace-regexp-in-string "[^[:alnum:] ]" " " (downcase (or s ""))))
   " "))

(defun diogenes--search-name-match-p (wanted listed)
  "Whether WANTED names the same thing as LISTED, both already loosened.

EQUALITY WILL NOT DO, and the PHI shows why twice over.  It heads a result

    M. Tullius Cicero, De Finibus

and lists the author as

    Marcus Tullius Cicero Cicero Tully (0474)

-- the praenomen spelled out where the header abbreviates it, and two
alternative names appended, `Cicero\=' again and `Tully\='.  Neither string is
the other and no stripping reaches between them.

SO: EVERY WORD OF WANTED, IN ORDER, SOMEWHERE IN LISTED.  A word of one
letter matches a word beginning with it, which is what an abbreviated
praenomen is -- `m\=' for `marcus\=' -- and a longer word must match whole, so
`cicero\=' does not match `ciceronianus\='.  What LISTED has besides is
ignored, aliases being no reason to fail.

In order, and not as a set: `Marcus Tullius Cicero\=' and
`Cicero Tullius Marcus\=' are not the same name, and a corpus that listed both
would want telling apart."
  (let ((want (split-string (or wanted "")))
	(have (split-string (or listed ""))))
    (and want
	 (catch 'no
	   (dolist (w want)
	     (let ((found nil))
	       (while (and have (not found))
		 (let ((h (car have)))
		   (setq have (cdr have))
		   (when (if (= 1 (length w))
			     (string-prefix-p w h)
			   (equal w h))
		     (setq found t))))
	       (unless found (throw 'no nil))))
	   t))))

(defun diogenes--search-citation-by-name (header-lines)
  "The author and work numbers for HEADER-LINES, found by their names.

FOR A CORPUS THAT PRINTS NO NUMBERS.  A PHI result is headed
`M. Tullius Cicero, De Republica\=' -- the author, a comma, the work -- and
nowhere in the buffer is there a `(0474: 005)\=' for the regexp above to
find.  So the names are looked up instead, against the lists the corpus
itself gives: `M. Tullius Cicero (0474)\=' and `De Republica (005)\=', the
number in brackets being what is wanted and the rest being what matches.

COMPARED LOOSELY, on the alphanumeric words alone: a header prints
`M. Tullius Cicero\=' where the list may punctuate differently, and the stops
and commas are no part of the name.

Returns (AUTHOR WORK) as strings, or nil where either cannot be found --
which is not an error here, the caller having a message of its own."
  (let* ((first-line (car header-lines))
	 (parts (and first-line (split-string first-line "," t "[ \t]+")))
	 (author-name (car parts))
	 ;; THE REST AND NOT THE SECOND, a title being free to hold a comma.
	 (work-name (and (cdr parts)
			 (string-join (cdr parts) ", "))))
    (when (and author-name work-name diogenes--search-corpus)
      (let* ((options (list :type diogenes--search-corpus))
	     (wanted-author (diogenes--search-loosely author-name))
	     (named-p
	      (lambda (wanted)
		(lambda (entry)
		  (diogenes--search-name-match-p
		   wanted
		   (diogenes--search-loosely
		    (diogenes--search-strip-number (car entry)))))))
	     (author
	      (cadr (seq-find (funcall named-p wanted-author)
			      (ignore-errors
				(diogenes--get-author-list options))))))
	(when author
	  (let* ((wanted-work (diogenes--search-loosely work-name))
		 (work
		  (cadr (seq-find (funcall named-p wanted-work)
				  (ignore-errors
				    (diogenes--get-works-list options
							     author))))))
	    (when work (list author work))))))))

(defun diogenes--search-get-citation (pos)
  "Get the full citation of the entry at point."
  (let* ((header-lines (diogenes--search-get-header-lines pos))
	 (cit (mapcar (lambda (s) (and (string-match "\\S-+$" s)
				  (match-string-no-properties 0 s)))
		      (split-string (car (last header-lines))
				    ",")))
	 (author-and-work (if (string-match "(\\([0-9]+\\): \\([0-9]+\\)) *$"
					    (car header-lines))
			      (list (match-string-no-properties 1 (car header-lines))
				    (match-string-no-properties 2 (car header-lines)))
			    ;; BACK TO THE LAST FULL HEADER, WITH NOERROR.
			    ;; Diogenes names the author and work once and
			    ;; the entries after carry a short header, which
			    ;; is why this looks back.  Without NOERROR it
			    ;; signalled search-failed with the regexp in the
			    ;; message, from a command pressed on a line that
			    ;; looked like any other -- and it happens
			    ;; wherever no full header is above: the preamble
			    ;; before the first entry, or a narrowed buffer.
			    (save-excursion
			      (if (re-search-backward
				   "(\\([0-9]+\\): \\([0-9]+\\)) *$" nil t)
				  (list (match-string-no-properties 1)
					(match-string-no-properties 2))
				;; OR BY NAME, THE NUMBERS NOT BEING PRINTED
				;; AT ALL IN SOME CORPORA.  A PHI search
				;; heads its results
				;;
				;;     M. Tullius Cicero, De Republica
				;;     book 1, section 27, line 13
				;;
				;; with no (0474: 005) anywhere in the
				;; buffer, so the search above can never
				;; succeed and every result was unbrowsable.
				;; The names are there, though, and the
				;; corpus will say what it numbers them.
				(or (diogenes--search-citation-by-name
				     header-lines)
				    (user-error
				     (concat "Cannot tell which author and"
					     " work this result is from"))))))))
    (nconc author-and-work cit)))

;;; Search mode commands
(defun diogenes-search-next (pos)
  "Move to the beginning of the next passage found."
  (interactive "d")
  (goto-char (cadr (diogenes--search-next-entry pos))))

(defun diogenes-search-previous (pos)
  "Move to the beginning of the previous passage found."
  (interactive "d")
  (goto-char (cadr (diogenes--search-previous-entry pos))))

(defun diogenes-search-delete (pos)
  "Delete the passage at point."
  (interactive "d")
  (diogenes--search-delete-entry pos))

(defun diogenes-search-browse-passage (pos)
  "Open the passage at point in the browser"
  (interactive "d")
  (diogenes--browse-work (list :type diogenes--search-corpus)
			 (diogenes--search-get-citation pos)))




;; --------------------------------------------------------------------
;;; SIMPLE SEARCH
(defun diogenes--search-sentinel (process event)
  (when (buffer-live-p (process-buffer process))
   (with-current-buffer (process-buffer process)
     (pcase event
       ("finished\n"
	(save-excursion
	  (let ((inhibit-read-only t))
	    (goto-char (point-max))
	    (re-search-backward "\nPassages found: \\([0-9]+\\).*")
	    (replace-match (concat "\nPassages found: "
				   (propertize (match-string-no-properties 1)
					       'font-lock-face 'success))))))))))

(defun diogenes--do-search (options &optional authors)
  "Function that executes a search query in the Diogenes Databases."
  (diogenes--start-perl "search"
			(diogenes--search-script options authors)
			#'diogenes--search-filter
			#'diogenes--search-sentinel)
  (diogenes-search-mode)
  (setq diogenes--search-active-block 'header)
  (setq diogenes--search-corpus (plist-get options :type))
  (setq diogenes--search-language
	(diogenes--probable-corpus-language diogenes--search-corpus)))

(defun diogenes--search-select-authors (type &optional simple callback)
  "Select a custom sub-corpus of TYPE.
When SIMPLE is supplied, construct a simple corpus manually. If
FUNCTION is supplied, allow the user to edit the corpus manually.
We he submits the corpus, call CALLBACK"
  (let ((corpus (unless (y-or-n-p (format "Search the whole %s? " type))
		  (if simple
		      (diogenes--define-simple-corpus type)
		    (diogenes--new-user-corpus type)))))
    (cond (callback (diogenes--edit-user-corpus-or-execute corpus callback))
	  (corpus   (list :author-nums (plist-get corpus :authors))))))

(defun diogenes--search-database (type &optional
				       options-or-pattern author-plist prefix)
  "Search for a phrase in Diogenes database using the Diogenes Perl Module.

This function is the generic dispacher for all corpora."
  (cond ((eql prefix 1)
	 (setf options-or-pattern
	       (list :pattern
		     (diogenes--process-pattern
		      (read-from-minibuffer "Enter search term: ")))))
	(prefix
	 (let ((patterns
		(cl-loop for pat = (diogenes--process-pattern
				    (read-from-minibuffer "With pattern: "))
			 then (diogenes--process-pattern
			       (read-from-minibuffer "And with pattern: "))
			 until (string-blank-p pat) collect pat))
	       (reject-pattern (read-from-minibuffer "Without pattern: "))
	       (context
		(completing-read "In context: "
				 (append
				  '(("sentence" . "sent")
				    ("paragraph" . "para")
				    ("1 line" . 1))
				  (cl-loop for i from 2 upto 100 collect
					   (cons (format "%d lines" i) i)))
				 nil t nil nil "sent"))
	       (min-matches (read-number "Minimum matches in context: " 1)))
	   (setf options-or-pattern
		 (append (when patterns `(:pattern-list ,patterns))
			 (when reject-pattern `(:reject-pattern ,reject-pattern))
			 (when context `(:context ,context))
			 (when min-matches `(:min-matches ,min-matches))))))
	((stringp options-or-pattern)
	 (setf options-or-pattern (list :pattern options-or-pattern)))
	((not (plistp options-or-pattern))
	 (error "%s must be either a string (pattern) or a plist!"
		options-or-pattern)))
  (setf options-or-pattern (plist-put options-or-pattern :type type))
  (diogenes--do-search options-or-pattern
		       (or author-plist
			   (diogenes--search-select-authors type
							    (eql prefix 1)))))


;;--------------------------------------------------------------------
;;;; WORDLIST SEARCH
(defun diogenes--indexed-search-sentinel (process event)
  (when (buffer-live-p (process-buffer process))
    (with-current-buffer (process-buffer process)
      (pcase event
	("finished\n"
	 (save-excursion
	   (let ((inhibit-read-only t))
	     (goto-char (point-max))
	     (re-search-backward
	      "\nIncidence of all words as reported by word list: \\([0-9]+\\).*")
	     (replace-match (concat
			     "\nIncidence of all words as reported by word list: "
			     (propertize (match-string-no-properties 1)
					 'font-lock-face 'success)))
	     (re-search-forward
	      "\nPassages containing those words reported by Diogenes: \\([0-9]+\\).*")
	     (replace-match
	      (concat "\nPassages containing those words reported by Diogenes: "
		      (propertize (match-string-no-properties 1)
				  'font-lock-face 'success))))))))))

(defun diogenes--do-wordlist-search (options words &optional authors)
  "Function that executes an indexed search query in the Diogenes Databases."
  (diogenes--start-perl "search"
			(diogenes--indexed-search-script options words authors)
			#'diogenes--search-filter
			#'diogenes--indexed-search-sentinel)
  (diogenes-search-mode)
  (setq diogenes--search-active-block 'header)
  (setq diogenes--search-corpus (plist-get options :type))
  (setq diogenes--search-language
	(diogenes--probable-corpus-language diogenes--search-corpus)))

(defun diogenes--tlg-wordlist-search (&optional pattern-or-forms authors)
  (let ((pattern-or-forms
	 (or pattern-or-forms
	     (read-from-minibuffer
	      "Please enter a pattern for searching the TLG word-list: "))))
    (cl-typecase pattern-or-forms
      (string
       (diogenes--select-from-tlg-wordlist
	pattern-or-forms
	(lambda (l) (diogenes--tlg-wordlist-search l authors))
	(format "Entries in the TLG word list matching %s:"
		pattern-or-forms)))
      (list 
       (let ((callback
	      (lambda (corpus)
		(diogenes--do-wordlist-search
		 (list :type "tlg")
		 pattern-or-forms
		 (when corpus
		   (list :author-nums
			 (plist-get corpus :authors)))))))
	 (cond (authors
		(funcall callback (list :authors authors)))
	       ((y-or-n-p "Search the whole TLG? ")
		(funcall callback nil))
	       ;; A TRANSIENT SUFFIX, CALLED FROM LISP.  It is interactive-only
	       ;; and this hands it a scope plist; reaching some inner
	       ;; non-interactive function instead would change how the corpus
	       ;; prompt works, so the warning is suppressed and not the code.
	       (t (with-suppressed-warnings
		      ((interactive-only diogenes--tr--create-user-corpus))
		    (diogenes--tr--create-user-corpus
		     (list :type "tlg"
			   :callback callback)))))))
      (t (error "Invalid type %s" pattern-or-forms)))))


;;--------------------------------------------------------------------
;;;; MORPHOLOGICAL SEARCH
(defun diogenes--lemma-forms-list (lemma lang)
  "Returns a list of all attested forms of LEMMA in LANG."
  (let ((entry (let ((lemmata (or (diogenes--get-all-forms lemma lang)
				  (error "No results for %s" lemma))))
		 (if (> (length lemmata) 1)
		     (assoc (completing-read "Please choose a lemma: "
					     lemmata)
			    lemmata)
		   (car lemmata)))))
    (cl-remove-duplicates (mapcar #'car (cdddr entry)))))

(defun diogenes--lemma-regexp (lemma lang &optional retain-diacritics)
  "Returns a regexp that matches all forms of a given lemma."
  (regexp-opt
   (mapcar (lambda (e)
	     (funcall (if retain-diacritics
			  #'identity
			#'diogenes--strip-diacritics)
		      (funcall (if (string= lang "greek")
				   #'diogenes--beta-to-utf8
				 #'identity)
			       e)))
	   (diogenes--lemma-forms-list lemma lang))))

(defun diogenes--morphological-search (type &optional lemma-or-forms authors)
  (let ((lemma-or-forms
	 (or lemma-or-forms
	     (read-from-minibuffer
	      (format "Please enter a lemma for searching the %s: "
		      (upcase type))))))
    (cl-typecase lemma-or-forms
      (string
       (diogenes--select-forms (diogenes--utf8-to-beta lemma-or-forms)
			       (diogenes--probable-corpus-language type)
			       (lambda (l) (diogenes--morphological-search type
								      l
								      authors))
			       (format "Search for the following forms of %s:"
				       lemma-or-forms)))
      (list 
       (let* ((forms (mapcar #'diogenes--utf8-to-beta lemma-or-forms))
	      (callback
	       (pcase type
		 ("tlg"
		  (lambda (corpus)
		    (diogenes--do-wordlist-search
		     (list :type type)
		     forms
		     (when corpus
		       (list :author-nums
			     (plist-get corpus :authors))))))
		 (_
		  (lambda (corpus)
		    (diogenes--do-search
		     (list :type type :pattern-list forms)
		      (when corpus
			(list :author-nums
			      (plist-get corpus :authors)))))))))
	 (cond (authors
		(funcall callback (list :authors authors)))
	       ((y-or-n-p (format "Search the whole %s? " type))
		(funcall callback nil))
	       (t (with-suppressed-warnings
		      ((interactive-only diogenes--tr--create-user-corpus))
		    (diogenes--tr--create-user-corpus
		     (list :type type
			   :callback callback)))))))
      (t (error "Invalid type %s" lemma-or-forms)))))



;;--------------------------------------------------------------------
;;;; TRANSIENT DISPATCHER
(transient-define-prefix diogenes--search-test ()
  "A simple test dispatcher."
  ["Test Dispatcher"
   ("g" "Search TLG"
    (lambda () (interactive)
      )
    :transient transient--do-recurse)
   ("l" "Search PHI"
    (lambda () (interactive)
      (transient-setup 'diogenes--search--select-mode nil nil
		       :scope (list :type "phi")))
    :transient transient--do-recurse)
   ("d" "Search the Duke Documentary Papyri"
    (lambda () (interactive)
      (transient-setup 'diogenes--search--select-mode nil nil
		       :scope (list :type "ddp")))
    :transient transient--do-recurse)
   ("i" "Search the Classical Inscriptions"
    (lambda () (interactive)
      (transient-setup 'diogenes--search--select-mode nil nil
		       :scope (list :type "ins")))
    :transient transient--do-recurse)
   ("c" "Search the Christian Inscriptions"
    (lambda () (interactive)
      (transient-setup 'diogenes--search--select-mode nil nil
		       :scope (list :type "chr")))
    :transient transient--do-recurse)
   ("m" "Search the Miscellaneous PHI Texts"
    (lambda () (interactive)
      (transient-setup 'diogenes--search--select-mode nil nil
		       :scope (list :type "misc")))
    :transient transient--do-recurse)])

(transient-define-prefix diogenes--search--select-mode (scope)
  "Select the mode of the search, and dispatch."
  [:description
   (lambda () (format "Select the mode for searching the %s" (upcase (diogenes--tr--type))))
   [("s" "Simple"   (lambda () (interactive) (diogenes--simple-search
					 (diogenes--tr--type))))
    ("l" "Lemma"    (lambda () (interactive) (diogenes--morphological-search
					 (diogenes--tr--type))))
    ("a" "Advanced" diogenes--advanced-search :transient transient--do-stay)
    ("w" "Wordlist" (lambda () (interactive) (diogenes--tlg-wordlist-search))
     :if (lambda () (string= (diogenes--tr--type) "tlg")))]]
  (interactive (list (if transient--prefix (diogenes--tr--type)
		       (list :type (diogenes--select-database)))))
  (transient-setup 'diogenes--search--select-mode nil nil :scope scope))

(transient-define-argument diogenes--search-mode-infix ()
  "Infix for choosing the search mode."
  :class 'transient-option
  :allow-empty nil
  :argument ""
  ;; :argument-format "%s"
  ;; :argument-regexp "simple\\|wordlist\\|lemma"
  :choices '("simple" "wordlist" "lemma")
  :init-value (lambda (obj) (oset obj value "simple"))
  :format "%k %d %v"
  :always-read t
  :unsavable t)

(defun diogenes--simple-search (type &optional pattern author-plist)
  "Start a simple search in corpus of TYPE."
  (diogenes--do-search
   (list :type type
	 :pattern (or pattern
		      (diogenes--process-pattern
		       (read-from-minibuffer "Enter search term: "))))
   (or author-plist
       (unless (y-or-n-p (format "Search the whole %s corpus? " type))
	 (list :author-nums
	       (diogenes--select-author-nums (list :type type)))))))

(defun diogenes--read-search-term (prompt &optional _initial-input _history)
  "Read search term for use in transient interface"
  (cl-labels ((reader (prompt)
		(let ((inp (read-from-minibuffer prompt)))
		  (if (not (string-blank-p inp))
		      (format "\"%s\"" inp)
		    (message "Input must not be blank!")
		    (sit-for 0.5)
		    (reader prompt)))))
    (catch 'minibuffer-quit (reader prompt))))

(transient-define-argument diogenes--search-pattern ()
  "Enter a search pattern."
  :class 'transient-option
  :description "With pattern"
  :format " %k  %v"
  :prompt "With pattern: "
  :reader 'diogenes--read-search-term
  :always-read t)

(transient-define-argument diogenes--minimum-matches ()
  "The minium number of matches in the defined context"
  :class 'transient-option
  :description "Minimum matches"
  :argument "minimum matches: "
  :format " %k  %v"
  :prompt "Minium matches: "
  :reader 'transient-read-number-N+
  :always-read t
  :init-value (lambda (obj) (oset obj value "1")))

(transient-define-argument diogenes--in-context ()
  "The context of the search"
  :class 'transient-option
  :description "In context"
  :argument "in context:      "
  :format " %k  %v"
  :prompt "In context: "
  :reader
  (lambda (prompt initial-input history)
    (completing-read prompt
		     (append '(("sentence" . "sent")
			       ("paragraph" . "para")
			       ("1 line" . 1))
			     (cl-loop for i from 2 upto 100
				      collect
				      (cons (format "%d lines" i)
					    i)))
		     nil t initial-input history "sent"))
  :always-read t
  :init-value (lambda (obj) (oset obj value "sentence")))

(transient-define-argument diogenes--input-lang ()
  "The input language.
For this to work, `dynamic-type' has to be dynamically bound to
the the corpus (TYPE) that is to be searched"
  :class 'transient-option
  :description "The input language"
  :argument "input language:  "
  :format " %k  %v"
  :prompt "Select input language: "
  :always-read t
  :allow-empty nil
  :choices '("greek" "latin" "coptic")
  :init-value (lambda (o)
		(when (diogenes--tr--type)
		  (oset o value
			(format "%s"
				(diogenes--probable-corpus-language
				 (diogenes--tr--type)))))))

(transient-define-argument diogenes--input-encoding ()
  "The input encoding."
  :class 'transient-option
  :description "The input encoding"
  :argument "input encoding:  "
  :format " %k  %v"
  :prompt "Select input encoding: "
  :always-read t
  :allow-empty nil
  :choices '("Unicode" "BETA code" "raw")
  :init-value (lambda (o) (oset o value "Unicode")))

(defun diogenes--search--ad-pattern (_pattern)
  (interactive "sWith pattern: ")
  (transient-insert-suffix 'diogenes--advanced-search
    '(0 0)
    (list "p" #'pwd))
  (transient-setup 'diogenes--advanced-search))


;; TODO: input-pure, input-raw
(transient-define-prefix diogenes--advanced-search (scope &optional patterns)
  "Start a advanced search."
  [:description
   (lambda () (format "ADVANCED %s SEARCH" (upcase (or (diogenes--tr--type) ""))))
   ;; :setup-children (lambda (_) dynamic-pattern-group)
   :class transient-column
   ("r" diogenes--search-pattern :argument "reject pattern: "
    :prompt "Without pattern: " :format " %k   %v")
   ]
  [("c" diogenes--in-context)
   ("m" diogenes--minimum-matches)
   ("l" diogenes--input-lang)
   ("e" diogenes--input-encoding)]
  [("<RET>" "DO SEARCH"
    (lambda () (interactive)
      (let* ((type (diogenes--tr--type))
	     (arg->key '(("reject pattern"  . :reject-pattern)
			 ("in context"      . :context)
			 ("minimum matches" . :min-matches)
			 ("input language"  . :input-lang)
			 ("input encoding"  . :input-encoding)))
	     (options
	      (cl-loop
	       with pattern-list
	       with options
	       for entry in (transient-args 'diogenes--advanced-search)
	       for (key val) = (diogenes--split-once ":[[:space:]]+" entry)
	       if (string-prefix-p "pattern" key)
	       do (push (substring val 1 -1) pattern-list)
	       else do
	       (progn (push (cdr (assoc key arg->key))
			    options)
		      (push (if (string= key "reject pattern")
				(substring val 1 -1)
			      val)
			    options))
	       finally return (nconc (list :type type
					   :pattern-list
					   (nreverse pattern-list))
				     (nreverse options))))
	     (callback
	      (lambda (corpus)
		(diogenes--do-search options
				     (when corpus
				       (list :author-nums
					     (plist-get corpus :authors)))))))
	(print options)
	(cond ((not (plist-get options :pattern-list))
	       (message "You have to specify at least one pattern!")
	       (transient-set)
	       (transient-setup 'diogenes--advanced-search nil nil :scope (transient-scope)))
	      ((y-or-n-p (format "Search the whole %s? " type))
	       (funcall callback nil))
	      (t (with-suppressed-warnings
		     ((interactive-only diogenes--tr--create-user-corpus))
		   (diogenes--tr--create-user-corpus (list :type type
							   :callback callback))))))))]
  (interactive (list (or (ignore-errors (transient-scope))
			 (list :type (diogenes--select-database)))
		     (cl-loop for pat = (diogenes--process-pattern
					 (read-from-minibuffer "With pattern: "))
			      then (diogenes--process-pattern
				    (read-from-minibuffer "And with pattern: "))
			      until (string-blank-p pat) collect pat)))
  ;; Somewhat hacky solution...
  (cl-loop for i from 0 to 25 do
	   (transient-remove-suffix 'diogenes--advanced-search
	     (list 0 (format "p%c" (+ i 97)))))
  (cl-loop for i from 0
	   for c from 97
	   for pattern in patterns
	   while pattern do
	   (transient-insert-suffix 'diogenes--advanced-search
	     (list 0 i)
	     ;; There seems to be a bug in transient that
	     ;; 'marks' all entries of the same argument when
	     ;; prompting for the new value. Therefore, we
	     ;; cannot use the diogenes--search-pattern
	     ;; argument here, but set it manually.
	     `(,(format "p%c" c)
	       "With pattern"
	       ,(format "pattern %d: " (1+ i))
	       :class transient-option
	       :format " %k  %v"
	       :prompt "With pattern: "
	       :reader diogenes--read-search-term
	       :init-value
	       (lambda (o) (oset o value
			    ,(format "\"%s\"" pattern))))))
  (transient-setup 'diogenes--advanced-search nil nil :scope scope))

(provide 'diogenes-search)

;;; diogenes-search.el ends here

