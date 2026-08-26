;;; diogenes-user-interface.el --- User interface for diogenes.el -*- lexical-binding: t -*-

;; Copyright (C) 2024 Michael Neidhart
;;
;; Author: Michael Neidhart <mayhoth@gmail.com>
;; Keywords: classics, tools, philology, humanities

;;; Commentary:

;; This file contains functions that provide the user interface of diogenes.el

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'diogenes-lisp-utils)

;; Called across files that cannot be required from here without a
;; cycle, and -- where the name is one of this package's own caches --
;; defined inside a `let', which the compiler does not count as a
;; definition at all.
(declare-function diogenes--get-author-list "diogenes-perl-interface" (options &optional regex))
(declare-function diogenes--get-works-list "diogenes-perl-interface" (options author))
(declare-function diogenes--get-work-labels "diogenes-perl-interface" (options author work))
(declare-function diogenes--get-tlg-categories "diogenes-perl-interface" ())

;;; Selectors
(defun diogenes--select-database ()
  "Select a Diogenes database using a prompt."
  (let ((completion-extra-properties
	 '(:annotation-function
	   (lambda (s)
	     (concat "\t"
		     (cdr (assoc s minibuffer-completion-table)))))))
    (completing-read "Please choose search corpus: "
		     diogenes--corpora nil t)))

(defun diogenes--select-author-num (options &optional author-regex)
  "Select one author from a diogenes database using a prompt.
REQUIRE-MATCH is passed to `completing-read', and has to be: the answer is
looked up in the list with `assoc', so anything not in the list resolves to
nil and the nil travels on to be a type error further down.  Without it,
plain Emacs completion returns whatever was typed -- a partial name and
RET is an answer, and not one this can use.  Helm, Ivy and Vertico all
select the highlighted candidate instead, which is why the fault showed
only where none of them was installed."
  (let ((author-list (diogenes--get-author-list options author-regex)))
    (unless author-list
      (user-error "No authors found in this database"))
    (cadr (assoc (completing-read "Author: " author-list nil t)
		 author-list))))

(defun diogenes--select-work-num (options author)
  "Select a single work from an author in a Diogenes database.
REQUIRE-MATCH, for the reason given in `diogenes--select-author-num'."
  (let ((works-list (diogenes--get-works-list options author)))
    (unless works-list
      (user-error "No works found for this author"))
    (cadr (assoc (completing-read "Work: " works-list nil t)
		 works-list))))

(defun diogenes--select-passage (options author work)
  "Select a specific passage from a given work in the Diogenes database."
  (let ((work-labels (diogenes--get-work-labels options (list author work))))
    (cl-loop for label in work-labels
	     collect (read-string (format "%s: " label)))))

(defun diogenes--select-tlg-categories ()
  (let* ((categories (diogenes--get-tlg-categories))
	 (category (intern
		    (completing-read "Select an category: "
				     (diogenes--plist-keys categories) nil t))))
    (completing-read "Please select: "
		     (plist-get categories category) nil t)))


;;; TODO: Selection with multiple regexes
(defun diogenes--select-author-nums (options &optional author-regex)
  "Select a list of authors from a diogenes database using a prompt.
Returns an array."
  (vconcat (cl-loop collect (diogenes--select-author-num options author-regex)
		    while (y-or-n-p "Add another author?"))))

;;; TODO: Selection with transient
(defun diogenes--select-authors-and-works (options &optional author-regex)
  "Select a list of authors and works from a diogenes database using a prompt.
Returns a plist."
  ())


(provide 'diogenes-user-interface)

;;; diogenes-user-interface.el ends here

