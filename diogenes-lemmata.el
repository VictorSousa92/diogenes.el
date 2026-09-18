;;; diogenes-lemmata.el --- the Perseus word lists -*- lexical-binding: t -*-

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

;; THE WORD LISTS, AND NOT THE DICTIONARIES.  Diogenes ships, beside its
;; lexica, a list per language of every attested form of every lemma.
;; `diogenes--get-all-forms' reads it; `diogenes-forms.el' and
;; `diogenes-search.el' are what want it, for a morphological search and for
;; the list of forms a lemma is searched by.

;; It lived in `diogenes-perseus.el', which is a thousand lines of dictionary
;; machinery those two files never touch: each needed one function from it and
;; required the whole.  Here they require this instead, and
;; `diogenes-perseus.el' becomes a leaf that nothing but `diogenes.el' loads.

;; `diogenes--perseus-path' comes here from `diogenes.el' for the same reason
;; read the other way: `diogenes-perseus.el' called up into the file that
;; requires it, which worked only because the call happens at run time.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'diogenes-lisp-utils)
(require 'diogenes-utils)

(defun diogenes--perseus-path ()
  (directory-file-name (file-name-concat (diogenes--path)
					 "dependencies"
					 "data")))


(defsubst diogenes--perseus-ensure-utf8 (str lang)
  (if (string= lang "greek")
      (diogenes--perseus-beta-to-utf8 str)
    (diogenes--replace-regexes-in-string str
      ("_" "\N{COMBINING MACRON}")
      ("\\^" "\N{COMBINING BREVE}"))))


(defun diogenes--lemmata-file-to-hashtable (file)
  "Loads a whole lemmata file into memory."
  (message "Parsing %s, this may take a while..." file)
  (with-temp-buffer
    (insert-file-contents-literally file)
    (prog1
	(cl-loop with lemmata = (make-hash-table :test 'equal :size 950000)
		 ;; with numbers = (make-hash-table :test 'equal :size 950000)
		 with begin = 1
		 for tab-1 = (re-search-forward "\t" nil t)
		 for tab-2 = (re-search-forward "\t" nil t)
		 ;; unless tab-2 return (cons lemmata numbers)
		 unless tab-2 return lemmata
		 for full-lemma = (buffer-substring begin (1- tab-1))
		 for lemma = (if (string-match "[0-9]$" full-lemma)
				 (substring full-lemma 0 (match-beginning 0))
			       full-lemma)
		 for nr  = (string-to-number (buffer-substring tab-1 (1- tab-2)))
		 for newline = (or (re-search-forward "\n" nil t)
				   (point-max))
		 for entries = (split-string (buffer-substring tab-2 (1- newline))
					     "\t")
		 for record = (nconc (list full-lemma nr) entries)
		 do (push record (gethash lemma lemmata))
		 ;; do (setf (gethash nr numbers)  record)
		 do (setf begin newline))
      (message "Parsed."))))


(defun diogenes--process-lemma (lemma lang)
  "Process a lemma entry as returned from `diogenes--get-all-lemmata'.
Returns a list with the form (lemma raw-lemma lemma-nr &rest analyses)"
  (when lemma
    (nconc (list (diogenes--perseus-ensure-utf8 (car lemma)
						lang)
		 (car lemma)
		 (cadr lemma))
	   (mapcar (lambda (e)
		     (seq-let (form analysis)
			 (diogenes--split-once "\\s-" e)
		       (cons (diogenes--perseus-ensure-utf8 form lang)
			     (with-temp-buffer
			       (insert analysis)
			       (goto-char (point-min))
			       (cl-loop with substrings
					for pos = (scan-sexps (point) 1)
					if pos
					collect (buffer-substring (1+ (point))
								  (1- pos))
					into substrings
					else return substrings
					do (goto-char (1+ pos)))))))
		   (cddr lemma)))))


(defun diogenes--get-all-forms (lemma lang)
  "Get all attested forms of LEMMA in LANG.
As there vould be several entries for the same lemma, this
function returns a list of lists."
  (mapcar (lambda (l) (diogenes--process-lemma l lang))
	  (gethash lemma (or (diogenes--get-all-lemmata lang)
			     (error "No lemmata retrieved for %s" lang)))))


(let ((cache (make-hash-table :test 'equal)))
  (defun diogenes--get-all-lemmata (lang)
    "Returns the entirety of a lemmata file as a hash table.
   This function is cached, so that it actually reads and parses
  the file only at the first call."
    (or (gethash (cons lang 'lemmata) cache)
  	(setf (gethash (cons lang 'lemmata) cache)
  	      (diogenes--lemmata-file-to-hashtable
  	       (file-name-concat (diogenes--perseus-path)
  				 (concat lang "-lemmata.txt")))))))

(provide 'diogenes-lemmata)

;;; diogenes-lemmata.el ends here
