;;; diogenes-legacy.el --- Lisp utilities for diogenes.el -*- lexical-binding: t -*-

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
  "Post-processes search results of diogenes"
  (interactive)
  (save-excursion
    (goto-char (point-min))
    ;; WAS `diogenes-unhyphen-greek', WHICH IS DEFINED NOWHERE -- so this
    ;; command was void-function at the keypress.  With no region active
    ;; `diogenes-remove-hyphenation' runs from point to the end of the
    ;; buffer, which is what the `goto-char' above asks for.
    (diogenes-remove-hyphenation)
    (goto-char (point-min))
    ;; `replace-regexp' IS FOR INTERACTIVE USE: it pushes the mark and
    ;; consults the case-replace machinery.  The loop is the documented
    ;; equivalent for a program.
    (while (re-search-forward "->\\([[:alpha:]]*\\)<-\\([[:alpha:]]*\\)" nil t)
      (replace-match "-> \\1\\2 -<"))))

(provide 'diogenes-legacy)

;;; diogenes-legacy.el ends here
