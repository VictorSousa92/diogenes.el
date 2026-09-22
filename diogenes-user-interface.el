;;; diogenes-user-interface.el --- User interface for diogenes.el -*- lexical-binding: t -*-

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

;; This file contains functions that provide the user interface of diogenes.el

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)                       ; string-trim, string-empty-p
(require 'diogenes-lisp-utils)
(require 'diogenes-perl-interface)       ; diogenes--get-author-list and c.

;; `diogenes.el' DEFINES THIS, and requires this file.
(defvar diogenes--corpora)

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
  "Select one author from a diogenes database using a prompt."
  (let ((author-list (diogenes--get-author-list options author-regex)))
    (cadr (assoc (completing-read "Author: " author-list nil t)
		 author-list))))

(defun diogenes--select-work-num (options author)
  "Select a single work from an author in a Diogenes database."
  (let ((works-list (diogenes--get-works-list options
					      author)))
    (cadr (assoc (completing-read "Work: "
				  works-list nil t)
		 works-list))))

(defun diogenes--select-passage (options author work)
  "Select a specific passage from a given work in the Diogenes database.

STOPS AT THE FIRST BLANK ANSWER, and this is the whole of the fix for a
crash.  It used to collect EVERY level, empty ones included, so a reader who
gave the book and not the line handed Perl `("2" "" "")\=' -- and an empty
string where `seek_passage\=' wants a number kills the process, which exits
255 and leaves a browser buffer that looks well and can do nothing.

Levels are given from the outside in -- book, then chapter, then line -- so a
blank means `no further\=', and asking for the levels under it is asking about
something the reader has already declined.  A passage of one level is
perfectly good: Diogenes opens that book at its beginning.

Trimmed, too: a level typed with a space after it is the same level."
  (let ((work-labels (diogenes--get-work-labels options (list author work))))
    (cl-loop for label in work-labels
	     for answer = (string-trim (read-string (format "%s: " label)))
	     until (string-empty-p answer)
	     collect answer)))

(defun diogenes--select-tlg-categories ()
  (let* ((categories (diogenes--get-tlg-categories))
	 (category (intern
		    (completing-read "Select an category: "
				     (diogenes--plist-keys categories) nil t))))
    (completing-read "Please select: " (plist-get categories category) nil t)))


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

