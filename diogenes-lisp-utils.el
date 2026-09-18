;;; diogenes-lisp-utils.el --- Lisp utilities for diogenes.el -*- lexical-binding: t -*-

;; Copyright (C) 2024 Michael Neidhart
;;
;; Author: Michael Neidhart <mayhoth@gmail.com>
;; Keywords: classics, tools, philology, humanities

;;; Commentary:

;; This file contains some lisp utilites needed by diogenes.el

;;; Code:
(require 'cl-lib)
(require 'transient)             ; transient-scope
(require 'seq)
(require 'ucs-normalize)                ; diogenes--ascii-alpha-only folds NFD

(defmacro diogenes--replace-regexes-in-string (str &rest subst-lists)
  "Apply a list of regex-substitutions to a string in sequence.
Each SUBST-LIST contains the REGEXP REP, followed optionaleval
parameters of `replace-regexp-in-string', FIXEDCASE LITERAL SUBEXP
START. Alternativly, SUBST-LIST can be a string or a list of one
element, in which case this is taken as the REGEXP and all of its
matches are deleted. 

Returns the resulting string."
  (declare (indent 1))
  (let ((result str))
    (dolist (subst subst-lists result)
      (setf result
	    (cl-typecase subst
	      (list (let ((regex (car subst))
			  (rep (or (cadr subst) ""))
			  (rest  (cddr subst)))
		      `(replace-regexp-in-string ,regex ,rep ,result
						 ,@rest)))
	      (string `(replace-regexp-in-string ,subst "" ,result))
	      (t (error "%s must be either a list or a string!"
			subst)))))))

(defun diogenes--plist-keys (plist)
  "Traverse a plist and extract its keys"
  (unless (plistp plist) (error "Not a plist!"))
  (cl-loop for key in plist by #'cddr
	   collect key))

(defun diogenes--plist-values (plist)
  "Traverse a plist and extract its values"
  (unless (plistp plist) (error "Not a plist!"))
  (cl-loop for key in (cdr plist) by #'cddr
	   collect key))

(defun diogenes--plist-keyword-keys-p (plist)
  "Check if all keys of a plist are keywords"
  (cond ((not (plistp plist)) nil)
	((cdr plist) (and (keywordp (car plist))
			  (diogenes--plist-keyword-keys-p (cddr plist))))
	(t t)))

(defun diogenes--assoc-cadr (key alist)
  "Return non-nil if KEY is equal to the cadr of an element of ALIST.
The value is actually the first element of ALIST whose car equals KEY."
  (cl-find-if (lambda (e) (equal key (cadr e)))
	      alist))

(defun diogenes--keyword->string (kw)
  (unless (keywordp kw) (error "Not a keyword: %s" kw))
  (substring (symbol-name kw) 1))

(defun diogenes--string->keyword (s)
  (intern (concat ":" s)))

(defun diogenes--hash-to-alist (hash-table)
  (cl-loop for k being the hash-keys of hash-table
	   using (hash-values v)
	   collect (cons k v)))

(defun diogenes--split-once (regexp str)
  "Split a string once on regexp and return the substrings as a list."
  (save-match-data
    (if (string-match regexp str)
	(list (substring str 0 (match-beginning 0))
	      (substring str (match-end 0)))
      (list str))))

(defun diogenes--get-text-prop-boundaries (pos property)
  "Get the boundaries of the region where property does not change."
  (let* ((end (or (next-single-char-property-change pos property)
	    (point-max)))
	 (start (or (previous-single-char-property-change end property)
		    (point-min))))
    (list start end)))

(defvar diogenes--loading-bundle nil
  "Non-nil while `diogenes.el' loads the dictionary modules it ships with.
This is how a module tells apart the two ways it can come to be loaded:

  the user asked for it -- `(require \\='diogenes-tll)' in an init file --
  which is a declaration that this dictionary is wanted;

  `diogenes.el' loaded it along with everything else, which says nothing
  about whether the user has it.

A module reads this AT LOAD TIME, through `diogenes--declared-at-load-p',
and passes the answer to `diogenes-lookup-register-dictionary' as
DECLARED.  Read at load time rather than at registration because
registration is deferred through `with-eval-after-load' and would
otherwise run inside the bundle's own binding.

`diogenes-declared-dictionaries' is the other way to declare one, and the
one that does not depend on load order.")

(defun diogenes--declared-at-load-p ()
  "Whether the file now being loaded was asked for, rather than bundled.
Call at the top level of a dictionary module, never from a function: the
answer is about the moment the file is read.  See
`diogenes--loading-bundle'."
  (not (bound-and-true-p diogenes--loading-bundle)))


;;;###autoload

;;;###autoload

;;;###autoload

;;;###autoload


;;;###autoload


(defun diogenes--path-set-p (value)
  "Non-nil if VALUE is a path the user has actually named.
Set-ness only: whether anything is there is not asked.  A dictionary whose
path is set is one the user means to have, so its link is offered and the
command explains what is wrong with the path -- a moved volume or a typo
being a thing to report rather than a reason to make the dictionary
disappear.  `diogenes--path-usable-p' is the stricter question, for when
something is about to be read."
  (and (stringp value) (not (string-empty-p value)) t))

(defun diogenes--source-set-p (value)
  "Non-nil if VALUE names TEI source material, without checking it is there.
As `diogenes--path-set-p', but for the `...-source-file' options, which
take a file, a directory of files, or a list of either."
  (cond
   ((consp value) (seq-some #'diogenes--source-set-p value))
   (t (diogenes--path-set-p value))))


(defun diogenes--path-usable-p (value kind)
  "Non-nil if VALUE names an existing file or readable directory.
KIND is `file' or `directory'.  VALUE is what a dictionary's path option
currently holds: nil, the empty string, or a path that does not exist all
count as unusable.

This is the half of the pair that ASKS, and it must stay cheap, silent and
free of side effects: the link banner calls it for every dictionary each
time it draws itself, so it may neither signal nor prompt.
`diogenes--require-path' is the half that TELLS -- called by a command once
the user has actually pressed a key, and which explains what to set."
  (and (stringp value)
       (not (string-empty-p value))
       (if (eq kind 'directory)
           (file-directory-p value)
         (file-readable-p value))
       t))

(defun diogenes--source-usable-p (value)
  "Non-nil if VALUE names TEI source material that is actually there.
The `...-source-file' options each take any of three things -- a single XML
file, a directory of them, or an explicit list -- so this accepts all
three: a list is usable when any of its members is, a string when it names
either a readable file or an existing directory.

Asked when deciding whether to offer a dictionary that has not been
converted yet: a source that is present means \\[diogenes-lookup-pape] and
its kind can offer to build the dictionary, so the link leads somewhere
after all.  Like `diogenes--path-usable-p', it neither signals nor
prompts."
  (cond
   ((consp value) (seq-some #'diogenes--source-usable-p value))
   (t (or (diogenes--path-usable-p value 'file)
          (diogenes--path-usable-p value 'directory)))))

(defun diogenes--require-path (value variable dictionary kind)
  "Return VALUE, or explain how to set VARIABLE if it will not serve.
The dictionaries each need a path from the user, and a missing one should
say what to set and how rather than failing somewhere downstream.  VALUE is
what the option currently holds, VARIABLE its symbol, DICTIONARY the name to
call it by in the message, and KIND either `file' or `directory'.

Set as an ordinary variable, before Diogenes loads, or through Customize;
either way the value survives the `defcustom'."
  (let ((name (symbol-name variable)))
    (cond
     ((or (null value) (and (stringp value) (string-empty-p value)))
      (user-error "%s is not set up yet: `%s' must name %s.  \
Put (setq %s \"/path/to/%s\") in your init file before Diogenes loads, or \
run M-x customize-variable RET %s RET"
                  dictionary name
                  (if (eq kind 'directory) "a directory" "a file")
                  name
                  (if (eq kind 'directory) "folder/" "file.pdf")
                  name))
     ((eq kind 'directory)
      (unless (file-directory-p value)
        (user-error "%s: `%s' is %s, which is not an existing directory"
                    dictionary name value))
      value)
     (t
      (unless (file-readable-p value)
        (user-error "%s: `%s' is %s, which cannot be read"
                    dictionary name value))
      value))))

(defun diogenes--ascii-alpha-p (letter)
  (or (<= 65 letter 90)
      (<= 97 letter 122)))

(defun diogenes--ascii-alpha-only (str)
  "Return the ASCII letters of STR, accented letters folded to their base.
Decomposes to NFD first, so a letter that carries a mark contributes the
letter: `desîmus' gives `desimus', not `desmus'.

That distinction is the whole point of the decomposition.  Everything but
ASCII letters is then discarded, and an accented letter that had NOT been
decomposed would be discarded with it -- so a Latin form printed with a
quantity or a contraction mark, as the PHI texts print `desîmus', lost the
marked letter altogether.  The comparators built on this then placed it
past the end of its own letter block (`desmus' sorts after `desivare'), and
a lookup landed on whatever entry happened to be there.

Ligatures are not spelt out here: NFD leaves æ alone, there being no
canonical decomposition for it.  A dictionary whose headwords use them
handles them in its own key function -- see `diogenes-gaffiot--key'."
  (cl-remove-if-not #'diogenes--ascii-alpha-p
                    (ucs-normalize-NFD-string (or str ""))))

(defun diogenes--string-equal-letters-only (str-a str-b)
  "Compare two string, making them equal if they contain the same letters"
  (string-equal (replace-regexp-in-string "[^[:alpha:]]" "" str-a)
		(replace-regexp-in-string "[^[:alpha:]]" "" str-b)))

(defun diogenes--first-line-p ()
  "Return non-nil if on the first line in buffer."
  (save-excursion (beginning-of-line) (bobp)))

(defun diogenes--last-line-p ()
  "Return non-nil if on the last line in buffer."
  (save-excursion (end-of-line) (eobp)))

(cl-defun diogenes--filter-in-minibuffer (list prompt
					       &key
					       initial-selection
					       remove-prompt
					       all-string
					       remove-string
					       regexp-string
					       commit-string)
  "Filter a list interactively in minibuffer, with initial-selection preselected.
When supplied, the keyword arguments add additional strings with a special meaning:

- :all-string adds all values and toggles the other input mode (add <-> remove)
- :regexp-string causes the next input to be read in as a regexp
- :remove-string switches input mode to `remove'"
  (setq list (cl-copy-list list))
  (setq remove-prompt (or remove-prompt prompt))
  (let ((max-mini-window-height 0.8))
    (cl-loop
     with list-length = (length list)
     with current-list = (cl-set-difference list initial-selection)
     with remove = nil
     with results = (nreverse initial-selection)
     for collection = (append (if remove results current-list)
			      (when regexp-string
				(list regexp-string))
			      (when (and remove-string
					 results
					 (not remove)) 
				(list remove-string))
			      (when (and all-string
					 (or remove
					     (< (length results)
						list-length)))
				(list all-string))
			      (when commit-string (list commit-string)))
     for inp = (completing-read (concat
				 (if results (format "%s\n" results) "")
				 (if remove remove-prompt prompt))
				collection)
     if (or (string-blank-p inp)
	    (equal inp commit-string))
     return (nreverse results)
     for matcher = (cond ((string= inp regexp-string)
			  (setq inp "")
			  (let ((regexp (read-regexp "Regexp: ")))
			    (lambda (str) (string-match regexp str))))
			 (t (lambda (str) (string-equal inp str))))
     do
     (cond ((not (or (string-blank-p inp)
		     (member inp collection)))
	    (message "Invalid input!")
	    (sit-for 1))
	   ((string= inp remove-string)
	    (setq remove t))
	   ((and remove (string= inp all-string))
	    (setq remove nil
		  current-list (cl-copy-list list)
		  results nil))
	   ((string= inp all-string)
	    (setq current-list nil
		  results (cl-copy-list list)))
	   (remove
	    (let ((matches (cl-remove-if-not matcher results)))
	      (setq remove nil
		    current-list (nconc matches current-list)
		    results (cl-delete-if matcher results))))
	   (t
	    (let ((matches (cl-remove-if-not matcher current-list)))
	      (setq results (nconc matches results)
		    current-list (cl-delete-if matcher current-list))))))))

(defun diogenes-undo ()
  "Undo also when buffer is readonly."
  (interactive)
  (let ((inhibit-read-only t))
    (undo)))

(defun diogenes--quit ()
  (interactive) (kill-buffer))

(defun diogenes--ask-and-quit ()
  (interactive)
  (when (y-or-n-p "Discard edits and quit?")
    (kill-buffer)))

;;; Transient scope accessors
(defsubst diogenes--tr--type () (plist-get (transient-scope) :type))
(defsubst diogenes--tr--callback () (plist-get (transient-scope) :callback))
(defsubst diogenes--tr--no-ask () (plist-get (transient-scope) :no-ask))

;;; The window layer, moved
;; It is `classicist-windows.el' now: the layer places buffers for
;; every family in the suite and not for Diogenes alone.  Aliased
;; here rather than there, so that a file requiring Diogenes and not
;; the suite still finds the old names -- nine files in this package
;; call the displayer, `tei-diorisis.el' is the tenth, and
;; `diogenes-window-behaviour' is a defcustom a reader may have set.
(require 'classicist-windows)

(define-obsolete-function-alias 'diogenes--behaviour-action
                               'classicist--behaviour-action "suite")
(define-obsolete-function-alias 'diogenes--behaviour-for
                               'classicist--behaviour-for "suite")
(define-obsolete-function-alias 'diogenes--buffer-role
                               'classicist--buffer-role "suite")
(define-obsolete-function-alias 'diogenes--claim-buffer
                               'classicist--claim-buffer "suite")
(define-obsolete-function-alias 'diogenes--companion-role
                               'classicist--companion-role "suite")
(define-obsolete-function-alias 'diogenes--display-action
                               'classicist--display-action "suite")
(define-obsolete-function-alias 'diogenes--display-buffer
                               'classicist-display-buffer "suite")
(define-obsolete-function-alias 'diogenes--display-log
                               'classicist--display-log "suite")
(define-obsolete-variable-alias 'diogenes--display-log-before
                               'classicist--display-log-before "suite")
(define-obsolete-variable-alias 'diogenes--display-log-branch
                               'classicist--display-log-branch "suite")
(define-obsolete-variable-alias 'diogenes--display-log-detail
                               'classicist--display-log-detail "suite")
(define-obsolete-function-alias 'diogenes--display-split-anyway
                               'classicist--display-split-anyway "suite")
(define-obsolete-function-alias 'diogenes--gathering-action
                               'classicist--gathering-action "suite")
(define-obsolete-function-alias 'diogenes--gathering-p
                               'classicist--gathering-p "suite")
(define-obsolete-function-alias 'diogenes--home-buffer-p
                               'classicist--home-buffer-p "suite")
(define-obsolete-function-alias 'diogenes--remember-role
                               'classicist--remember-role "suite")
(define-obsolete-variable-alias 'diogenes--role-modes
                               'classicist--role-modes "suite")
(define-obsolete-function-alias 'diogenes--sole-home-window-p
                               'classicist--sole-home-window-p "suite")
(define-obsolete-function-alias 'diogenes--split-alist
                               'classicist--split-alist "suite")
(define-obsolete-function-alias 'diogenes--split-functions
                               'classicist--split-functions "suite")
(define-obsolete-function-alias 'diogenes--split-size-for
                               'classicist--split-size-for "suite")
(define-obsolete-function-alias 'diogenes--window-of-role
                               'classicist--window-of-role "suite")
(define-obsolete-function-alias 'diogenes--window-that-held
                               'classicist--window-that-held "suite")
(define-obsolete-function-alias 'diogenes--windows-of-role
                               'classicist--windows-of-role "suite")
;; diogenes--with-our-answer: a macro, and internal -- not aliased
(define-obsolete-variable-alias 'diogenes-browser-display-action
                               'classicist-browser-display-action "suite")
(define-obsolete-variable-alias 'diogenes-claim-buffer-function
                               'classicist-claim-buffer-function "suite")
(define-obsolete-variable-alias 'diogenes-claim-buffers
                               'classicist-claim-buffers "suite")
(define-obsolete-variable-alias 'diogenes-companion-direction
                               'classicist-companion-direction "suite")
(define-obsolete-variable-alias 'diogenes-companion-roles
                               'classicist-companion-roles "suite")
(define-obsolete-variable-alias 'diogenes-dictionary-display-action
                               'classicist-dictionary-display-action "suite")
(define-obsolete-function-alias 'diogenes-display-beside-companion
                               'classicist-display-beside-companion "suite")
(define-obsolete-variable-alias 'diogenes-display-debug
                               'classicist-display-debug "suite")
(define-obsolete-function-alias 'diogenes-display-in-role-frame
                               'classicist-display-in-role-frame "suite")
(define-obsolete-variable-alias 'diogenes-frame-parameters
                               'classicist-frame-parameters "suite")
(define-obsolete-variable-alias 'diogenes-gather-frames
                               'classicist-gather-frames "suite")
(define-obsolete-variable-alias 'diogenes-home-buffer-names
                               'classicist-home-buffer-names "suite")
(define-obsolete-variable-alias 'diogenes-lookup-display-action
                               'classicist-lookup-display-action "suite")
(define-obsolete-variable-alias 'diogenes-morphology-display-action
                               'classicist-morphology-display-action "suite")
(define-obsolete-variable-alias 'diogenes-role-regexps
                               'classicist-role-regexps "suite")
(define-obsolete-variable-alias 'diogenes-split-direction
                               'classicist-split-direction "suite")
(define-obsolete-variable-alias 'diogenes-split-from
                               'classicist-split-from "suite")
(define-obsolete-variable-alias 'diogenes-split-size
                               'classicist-split-size "suite")
(define-obsolete-variable-alias 'diogenes-window-behaviour
                               'classicist-window-behaviour "suite")

;;; The focus commands, moved
;; `classicist-windows.el' holds them now.  Aliased here so that a
;; reader who bound `diogenes-focus-browser' keeps their key, and so
;; that `diogenes-focus-keys' keeps its value.

(define-obsolete-variable-alias 'diogenes--focus-maps
                                'classicist--focus-maps "0.1")
(define-obsolete-function-alias 'diogenes--focus-role
                                'classicist--focus-role "0.1")
(define-obsolete-function-alias 'diogenes-focus-browser
                                'classicist-focus-browser "0.1")
(define-obsolete-function-alias 'diogenes-focus-dictionary
                                'classicist-focus-dictionary "0.1")
(define-obsolete-variable-alias 'diogenes-focus-keys
                                'classicist-focus-keys "0.1")
(define-obsolete-function-alias 'diogenes-focus-lookup
                                'classicist-focus-lookup "0.1")
(define-obsolete-function-alias 'diogenes-focus-morphology
                                'classicist-focus-morphology "0.1")
(define-obsolete-function-alias 'diogenes-install-focus-keys
                                'classicist-install-focus-keys "0.1")

(provide 'diogenes-lisp-utils)

;;; diogenes-lisp-utils.el ends here
