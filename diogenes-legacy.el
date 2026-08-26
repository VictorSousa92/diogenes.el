;;; diogenes-legacy.el --- Lisp utilities for diogenes.el -*- lexical-binding: t -*-

;; Copyright (C) 2024 Michael Neidhart
;;
;; Author: Michael Neidhart <mayhoth@gmail.com>
;; Keywords: classics, tools, philology, humanities

;;; Commentary:

;; Some legacy post-processing functions

;;; Code:

(require 'diogenes-utils)               ; diogenes-remove-hyphenation


;;;###autoload
(defun diogenes-delete-line-numbers ()
  "Delete line numbers, starting at point"
  (interactive)
  (save-excursion
    (let ((start (progn
                   (unless
                       (re-search-backward
                        "\([[:digit:]][[:digit:]][[:digit:]][[:digit:]]: [[:digit:]][[:digit:]][[:digit:]]\)"
                        nil t)
                     (re-search-forward
                      "\([[:digit:]][[:digit:]][[:digit:]][[:digit:]]: [[:digit:]][[:digit:]][[:digit:]]\)"))
                   (re-search-forward "^$")
                   (point)))
          (end (progn
                 ;; (goto-char (point-max))
                 (unless
                     (re-search-forward "diogenes-browse finished" nil t)
                   (goto-char (point-max)))
                 (re-search-backward "[Α‐ω]")
                 (beginning-of-line)
                 (forward-char 14)
                 (point))))
      (delete-rectangle start end))))

;;;###autoload
(defun diogenes-tidy-up-search-results ()
  "Post-process the search results in this buffer.
Joins words broken across lines, then closes up the ->word<- marks that
Diogenes puts around a hit, so the arrows sit outside the word.

The first step called `diogenes-unhyphen-greek\=', which is defined nowhere in
this package and never was -- so this command has always failed at its first
line with a void-function error.  `diogenes-remove-hyphenation\=' is the
function that does that work, and it is not specific to Greek.

`replace-regexp\=' is likewise gone: it is for interactive use, and warns when
called from Lisp."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (diogenes-remove-hyphenation)
    (goto-char (point-min))
    (while (re-search-forward "->\\([[:alpha:]]*\\)<-\\([[:alpha:]]*\\)" nil t)
      (replace-match "-> \\1\\2 -<"))))

(provide 'diogenes-legacy)

;;; diogenes-legacy.el ends here
